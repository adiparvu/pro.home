import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ─── track-webhook ────────────────────────────────────────────────────────────
// Receives status events from Ship24 and writes a NORMALIZED view of them onto
// `packages`. This is the ONLY place in the system that knows Ship24's payload
// shape — the iOS app and the database schema are provider-agnostic, so
// switching aggregators later means rewriting just this file (and track-register),
// with zero client or schema changes.
//
// It also fans each update out to any registered ActivityKit push tokens
// (`live_activity_tokens`, written by the app when a delivery Live Activity
// starts) with `apns-push-type: liveactivity`, so the Dynamic Island keeps
// moving while the phone is locked. APNs delivery is best-effort: a missing
// APNs configuration or a failed push never blocks the database write.
//
// Security: Ship24 is configured to call this URL with a shared secret in the
// query string (?secret=…) matching SHIP24_WEBHOOK_SECRET.
//
// Required secrets (no-op 503 until set):
//   SHIP24_WEBHOOK_SECRET                      – shared secret in the webhook URL
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY   – provided by the platform
// Optional (Live Activity pushes are skipped until set):
//   APNS_KEY_ID / APNS_TEAM_ID / APNS_PRIVATE_KEY / APNS_BUNDLE_ID
// ──────────────────────────────────────────────────────────────────────────────

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Ship24 statusMilestone -> the app's existing `status` column. Kept server-side
// so the client never encodes a provider's status vocabulary.
function legacyStatus(milestone: string): string {
  switch (milestone) {
    case 'delivered':            return 'delivered'
    case 'out_for_delivery':     return 'out_for_delivery'
    case 'available_for_pickup': return 'out_for_delivery'
    case 'exception':
    case 'failed_attempt':       return 'missed'
    default:                     return 'expected' // pending, info_received, in_transit…
  }
}

// The 4-segment journey the Live Activity renders (mirrors the app's mapping
// in LiveActivityService): 0 ordered · 1 in transit · 2 out · 3 delivered.
function milestoneIndex(milestone: string): number {
  switch (milestone) {
    case 'pending':
    case 'info_received':        return 0
    case 'in_transit':           return 1
    case 'out_for_delivery':
    case 'available_for_pickup':
    case 'failed_attempt':       return 2
    case 'delivered':            return 3
    default:                     return 1 // exception, expired mid-journey
  }
}

function isProblem(milestone: string): boolean {
  return milestone === 'exception' || milestone === 'failed_attempt' || milestone === 'expired'
}

// English fallback only — the widget resolves the label on-device from
// `status`, in the user's language.
function fallbackLabel(milestone: string): string {
  switch (milestone) {
    case 'pending':
    case 'info_received':        return 'Expected'
    case 'in_transit':           return 'In transit'
    case 'out_for_delivery':     return 'Out for delivery'
    case 'available_for_pickup': return 'Ready for pickup'
    case 'delivered':            return 'Delivered'
    case 'failed_attempt':       return 'Failed attempt'
    default:                     return 'Delivery issue'
  }
}

// ── APNs (same JWT machinery as send-chat-push) ──────────────────────────────

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

  const secret = Deno.env.get('SHIP24_WEBHOOK_SECRET')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!secret || !supabaseUrl || !serviceKey) {
    return json({ error: 'tracking not configured' }, 503)
  }

  // Shared-secret gate (Ship24 webhook URL is configured with ?secret=…).
  // Trim both sides: dashboards often append a trailing newline/space when a
  // secret is saved, which would otherwise fail an exact comparison.
  const url = new URL(req.url)
  const provided = (url.searchParams.get('secret') ?? '').trim()
  if (provided !== secret.trim()) return json({ error: 'unauthorized' }, 401)

  let payload: any
  try { payload = await req.json() } catch { return json({ error: 'bad request' }, 400) }

  // Ship24 posts { trackings: [ { tracker, shipment, events } ] }. Be defensive
  // about the envelope so provider quirks don't drop events.
  const trackings: any[] = payload?.trackings ?? payload?.data?.trackings ?? []
  if (!Array.isArray(trackings) || trackings.length === 0) return json({ ok: true, updated: 0 }, 200)

  const admin = createClient(supabaseUrl, serviceKey)
  let updated = 0
  let pushed = 0

  // Live Activity pushes are optional — skipped cleanly until APNs is set up.
  const apnsKeyId = Deno.env.get('APNS_KEY_ID')
  const apnsTeamId = Deno.env.get('APNS_TEAM_ID')
  const apnsP8 = Deno.env.get('APNS_PRIVATE_KEY')
  const apnsBundleId = Deno.env.get('APNS_BUNDLE_ID')
  const apnsReady = !!(apnsKeyId && apnsTeamId && apnsP8 && apnsBundleId)
  let apnsJwt: string | null = null

  for (const t of trackings) {
    const trackerId: string | undefined = t?.tracker?.trackerId
    const trackingNumber: string | undefined = t?.tracker?.trackingNumber
    const milestone: string = t?.shipment?.statusMilestone ?? 'pending'
    const events: any[] = Array.isArray(t?.events) ? t.events : []

    // Normalize the event timeline into our own shape (newest first).
    const checkpoints = events.map((e) => ({
      time: e?.occurrenceDatetime ?? e?.datetime ?? null,
      status: e?.status ?? e?.statusMilestone ?? '',
      message: e?.status ?? '',
      location: e?.location ?? null,
      milestone: e?.statusMilestone ?? null,
    })).sort((a, b) => String(b.time).localeCompare(String(a.time)))

    const eta: string | null =
      t?.shipment?.delivery?.estimatedDeliveryDate ??
      t?.shipment?.estimatedDeliveryDate ?? null
    const lastEventAt: string | null = checkpoints[0]?.time ?? null

    const patch: Record<string, unknown> = {
      live_status: milestone,
      status: legacyStatus(milestone),
      checkpoints,
      estimated_delivery: eta,
      last_event_at: lastEventAt,
      last_synced_at: new Date().toISOString(),
    }
    if (t?.shipment?.recipient?.courierCode || t?.shipment?.courierCode) {
      patch.courier_code = t?.shipment?.recipient?.courierCode ?? t?.shipment?.courierCode
    }

    // Match by tracker id first (stable), fall back to tracking number.
    let q = admin.from('packages').update(patch)
    q = trackerId ? q.eq('tracker_id', trackerId) : q.eq('tracking_number', trackingNumber ?? '')
    const { data, error } = await q.select('id')
    if (!error) updated += data?.length ?? 0

    // ── Fan out to Live Activity tokens for this tracker ────────────────────
    if (!apnsReady || !trackerId) continue

    const { data: tokens } = await admin
      .from('live_activity_tokens')
      .select('id, token, environment')
      .eq('tracker_id', trackerId)
    if (!tokens || tokens.length === 0) continue

    if (!apnsJwt) apnsJwt = await makeApnsJwt(apnsP8!, apnsKeyId!, apnsTeamId!)

    const top = checkpoints[0]
    const checkpointLine = top
      ? [top.message, top.location].filter((s) => s && String(s).length > 0).join(' · ') || null
      : null

    // Field names must match DeliveryActivityAttributes.ContentState exactly;
    // the widget localizes the label on-device from `status`.
    const contentState = {
      status: milestone,
      statusLabel: fallbackLabel(milestone),
      eta: eta ? String(eta).slice(0, 10) : null,
      milestoneIndex: milestoneIndex(milestone),
      checkpoint: checkpointLine,
      isProblem: isProblem(milestone),
    }

    const urgent = milestone === 'out_for_delivery' || isProblem(milestone)
    const ended = milestone === 'delivered'
    const aps: Record<string, unknown> = {
      timestamp: Math.floor(Date.now() / 1000),
      event: ended ? 'end' : 'update',
      'content-state': contentState,
      // Same relevance scale the app uses (LiveActivityService.Relevance):
      // a problem outranks a routine hop in the Dynamic Island.
      'relevance-score': isProblem(milestone) ? 90 : urgent ? 85 : 40,
    }
    // Delivered: keep the summary readable on the Lock Screen for half an
    // hour (HIG: "15 to 30 minutes is adequate"), not a blink-and-miss 30s.
    if (ended) aps['dismissal-date'] = Math.floor(Date.now() / 1000) + 1800
    if (urgent || ended) {
      aps.alert = {
        title: fallbackLabel(milestone),
        body: checkpointLine ?? (trackingNumber ?? ''),
      }
    }

    for (const row of tokens) {
      try {
        const res = await fetch(`https://${apnsHost(row.environment)}/3/device/${row.token}`, {
          method: 'POST',
          headers: {
            authorization: `bearer ${apnsJwt}`,
            'apns-topic': `${apnsBundleId}.push-type.liveactivity`,
            'apns-push-type': 'liveactivity',
            'apns-priority': urgent || ended ? '10' : '5',
          },
          body: JSON.stringify({ aps }),
        })
        if (res.ok) pushed++
        // A gone token (uninstalled app / ended activity) never comes back.
        if (res.status === 410) {
          await admin.from('live_activity_tokens').delete().eq('id', row.id)
        }
      } catch (_e) {
        // best-effort — the database write above is the source of truth
      }
    }
    if (ended) {
      await admin.from('live_activity_tokens').delete().eq('tracker_id', trackerId)
    }
  }

  return json({ ok: true, updated, pushed }, 200)
})

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}
