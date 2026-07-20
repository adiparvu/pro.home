import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ─── iot-event ────────────────────────────────────────────────────────────────
// Receives sensor events from the user's OWN controllers (ESP32 / RPi
// firmware calling this URL directly, or the app's "Phone Alert" automation)
// and turns them into: (1) a persisted row in iot_events, (2) an APNs alert
// push to the account's devices, and (3) `apns-push-type: liveactivity`
// updates for any registered IoT-alert Live Activity token — so a leak at
// 3 AM lights up the Dynamic Island with the phone locked and PRVIO closed.
//
// Security: per-account secret in the query string (?token=…), matched
// against iot_webhooks. Rows there are created by the signed-in app; this
// function only ever reads them with the service role.
//
// Body (JSON): { sensorId, name, type, event: "alert"|"clear",
//                value?, unit?, zone?, display? }
//
// Required secrets: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY (platform).
// Optional: APNS_KEY_ID / APNS_TEAM_ID / APNS_PRIVATE_KEY / APNS_BUNDLE_ID —
// without them the event is persisted but no push goes out.
// ──────────────────────────────────────────────────────────────────────────────

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const CRITICAL_TYPES = new Set(['smoke', 'gas', 'water'])

// ── APNs (same JWT machinery as send-chat-push / track-webhook) ──────────────

function b64url(bytes: Uint8Array): string {
  let bin = ''
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '')
  const bin = atob(b64)
  const buf = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i)
  return buf.buffer
}

async function makeApnsJwt(p8: string, keyId: string, teamId: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8(p8),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  )
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'ES256', kid: keyId })))
  const payload = b64url(new TextEncoder().encode(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) })))
  const signingInput = `${header}.${payload}`
  const sig = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput),
  )
  return `${signingInput}.${b64url(new Uint8Array(sig))}`
}

function apnsHost(environment: string): string {
  return environment === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com'
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceKey) return json({ error: 'not configured' }, 503)

  const url = new URL(req.url)
  const token = (url.searchParams.get('token') ?? '').trim()
  if (!token) return json({ error: 'unauthorized' }, 401)

  const admin = createClient(supabaseUrl, serviceKey)

  const { data: hook } = await admin
    .from('iot_webhooks')
    .select('user_id')
    .eq('secret', token)
    .maybeSingle()
  if (!hook?.user_id) return json({ error: 'unauthorized' }, 401)
  const userId: string = hook.user_id

  let body: any
  try { body = await req.json() } catch { return json({ error: 'bad request' }, 400) }

  const sensorId: string = String(body?.sensorId ?? '')
  const name: string = String(body?.name ?? 'Sensor')
  const type: string = String(body?.type ?? 'custom')
  const event: string = body?.event === 'clear' ? 'clear' : 'alert'
  const value: number | null = typeof body?.value === 'number' ? body.value : null
  const unit: string | null = body?.unit ? String(body.unit) : null
  const zone: string | null = body?.zone ? String(body.zone) : null
  const display: string = body?.display
    ? String(body.display)
    : value != null ? `${value}${unit ? ` ${unit}` : ''}` : name

  await admin.from('iot_events').insert({
    user_id: userId, sensor_id: sensorId || null, name, type,
    value, unit, zone, display, event,
  })

  const apnsKeyId = Deno.env.get('APNS_KEY_ID')
  const apnsTeamId = Deno.env.get('APNS_TEAM_ID')
  const apnsP8 = Deno.env.get('APNS_PRIVATE_KEY')
  const apnsBundleId = Deno.env.get('APNS_BUNDLE_ID')
  if (!apnsKeyId || !apnsTeamId || !apnsP8 || !apnsBundleId) {
    return json({ ok: true, pushed: 0, note: 'APNs not configured' }, 200)
  }
  const jwt = await makeApnsJwt(apnsP8, apnsKeyId, apnsTeamId)
  let pushed = 0

  // ── Live Activity updates (island moves with the phone locked) ────────────
  if (sensorId) {
    const { data: tokens } = await admin
      .from('live_activity_tokens')
      .select('id, token, environment')
      .eq('tracker_id', sensorId)
      .eq('activity_kind', 'iot_alert')
      .eq('user_id', userId)

    const cleared = event === 'clear'
    const aps: Record<string, unknown> = {
      timestamp: Math.floor(Date.now() / 1000),
      event: cleared ? 'end' : 'update',
      // Field names must match IoTAlertActivityAttributes.ContentState.
      'content-state': { valueDisplay: display, isActive: !cleared },
    }
    if (cleared) aps['dismissal-date'] = Math.floor(Date.now() / 1000) + 10

    for (const row of tokens ?? []) {
      try {
        const res = await fetch(`https://${apnsHost(row.environment)}/3/device/${row.token}`, {
          method: 'POST',
          headers: {
            authorization: `bearer ${jwt}`,
            'apns-topic': `${apnsBundleId}.push-type.liveactivity`,
            'apns-push-type': 'liveactivity',
            'apns-priority': '10',
          },
          body: JSON.stringify({ aps }),
        })
        if (res.ok) pushed++
        if (res.status === 410) {
          await admin.from('live_activity_tokens').delete().eq('id', row.id)
        }
      } catch (_e) { /* best-effort */ }
    }
    if (cleared) {
      await admin.from('live_activity_tokens')
        .delete().eq('tracker_id', sensorId).eq('activity_kind', 'iot_alert')
    }
  }

  // ── Plain alert push (reaches the user even with no island running) ───────
  if (event === 'alert') {
    const { data: devices } = await admin
      .from('device_tokens')
      .select('token, environment')
      .eq('user_id', userId)
      .eq('platform', 'ios')

    const critical = CRITICAL_TYPES.has(type)
    const payload = {
      aps: {
        alert: { title: name, body: zone ? `${display} · ${zone}` : display },
        sound: 'default',
        'thread-id': 'iot',
        'interruption-level': critical ? 'time-sensitive' : 'active',
      },
    }
    for (const t of devices ?? []) {
      try {
        const res = await fetch(`https://${apnsHost(t.environment)}/3/device/${t.token}`, {
          method: 'POST',
          headers: {
            authorization: `bearer ${jwt}`,
            'apns-topic': apnsBundleId,
            'apns-push-type': 'alert',
          },
          body: JSON.stringify(payload),
        })
        if (res.ok) pushed++
      } catch (_e) { /* best-effort */ }
    }
  }

  return json({ ok: true, pushed }, 200)
})

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}
