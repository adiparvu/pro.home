import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ─── send-chat-push ──────────────────────────────────────────────────────────
// Delivers unpushed chat notifications to native iOS devices via APNs.
//
// Invocation: protected by CRON_SECRET (x-cron-secret header). Intended to be
// called by a Database Webhook / pg_cron after a chat message is inserted, or
// on a short schedule.
//
// Required secrets (until these are set, the function is a no-op 503):
//   APNS_KEY_ID        – the 10-char Key ID of the APNs auth key (.p8)
//   APNS_TEAM_ID       – Apple Developer Team ID
//   APNS_PRIVATE_KEY   – contents of the AuthKey_XXXX.p8 (PEM, with headers)
//   APNS_BUNDLE_ID     – app bundle id (e.g. com.prvio.app) -> apns-topic
//   CRON_SECRET        – shared secret to authorize this endpoint
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY – provided by the platform
// ──────────────────────────────────────────────────────────────────────────────

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret',
}

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

  const keyId = Deno.env.get('APNS_KEY_ID')
  const teamId = Deno.env.get('APNS_TEAM_ID')
  const p8 = Deno.env.get('APNS_PRIVATE_KEY')
  const bundleId = Deno.env.get('APNS_BUNDLE_ID')
  const cronSecret = Deno.env.get('CRON_SECRET')

  if (!keyId || !teamId || !p8 || !bundleId) {
    return new Response(JSON.stringify({ error: 'APNs not configured' }), {
      status: 503,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
  if (!cronSecret || req.headers.get('x-cron-secret') !== cronSecret) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  )

  // Pull unpushed chat notifications.
  const { data: notes, error } = await admin
    .from('notifications')
    .select('id, user_id, title, body')
    .eq('module', 'chat')
    .is('pushed_at', null)
    .limit(200)

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
  if (!notes || notes.length === 0) {
    return new Response(JSON.stringify({ sent: 0 }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }

  const jwt = await makeApnsJwt(p8, keyId, teamId)
  const nowISO = new Date().toISOString()
  let sent = 0
  const pushedIds: string[] = []

  for (const n of notes) {
    const { data: tokens } = await admin
      .from('device_tokens')
      .select('token, environment')
      .eq('user_id', n.user_id)
      .eq('platform', 'ios')

    for (const t of tokens ?? []) {
      const payload = {
        aps: {
          alert: { title: n.title ?? 'New message', body: n.body ?? '' },
          sound: 'default',
          'thread-id': 'chat',
        },
      }
      try {
        const res = await fetch(`https://${apnsHost(t.environment)}/3/device/${t.token}`, {
          method: 'POST',
          headers: {
            authorization: `bearer ${jwt}`,
            'apns-topic': bundleId,
            'apns-push-type': 'alert',
          },
          body: JSON.stringify(payload),
        })
        if (res.ok) sent++
      } catch (_e) {
        // best-effort; leave pushed_at unset so a later run can retry
      }
    }
    pushedIds.push(n.id)
  }

  if (pushedIds.length > 0) {
    await admin.from('notifications').update({ pushed_at: nowISO }).in('id', pushedIds)
  }

  return new Response(JSON.stringify({ sent, processed: pushedIds.length }), {
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
})
