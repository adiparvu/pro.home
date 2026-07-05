import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ─── track-webhook ────────────────────────────────────────────────────────────
// Receives status events from AfterShip and writes a NORMALIZED view of them
// onto `packages`. This is the ONLY place in the system that knows AfterShip's
// payload shape — the iOS app and the database schema are provider-agnostic, so
// switching aggregators later means rewriting just this file (and track-register),
// with zero client or schema changes.
//
// Security: AfterShip signs each webhook with HMAC-SHA256 over the raw body,
// base64-encoded, in the `aftership-hmac-sha256` header. We verify it against
// AFTERSHIP_WEBHOOK_SECRET.
//
// Required secrets (no-op 503 until set):
//   AFTERSHIP_WEBHOOK_SECRET                   – webhook signing secret
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY   – provided by the platform
// ──────────────────────────────────────────────────────────────────────────────

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, aftership-hmac-sha256',
}

// AfterShip `tag` -> the app's existing `status` column. Keeping this mapping
// server-side means the client never encodes a provider's status vocabulary.
function legacyStatus(tag: string): string {
  switch (tag) {
    case 'Delivered':          return 'delivered'
    case 'OutForDelivery':     return 'out_for_delivery'
    case 'AvailableForPickup': return 'out_for_delivery'
    case 'Exception':
    case 'AttemptFail':
    case 'Expired':            return 'missed'
    default:                   return 'expected' // Pending, InfoReceived, InTransit
  }
}

// AfterShip `tag` -> our normalized live_status slug.
function liveStatus(tag: string): string {
  switch (tag) {
    case 'InfoReceived':       return 'info_received'
    case 'InTransit':          return 'in_transit'
    case 'OutForDelivery':     return 'out_for_delivery'
    case 'AvailableForPickup': return 'available_for_pickup'
    case 'Delivered':          return 'delivered'
    case 'AttemptFail':        return 'failed_attempt'
    case 'Exception':          return 'exception'
    case 'Expired':            return 'expired'
    default:                   return 'pending'
  }
}

async function validSignature(secret: string, raw: string, header: string | null): Promise<boolean> {
  if (!header) return false
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  )
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(raw))
  let bin = ''
  for (const b of new Uint8Array(sig)) bin += String.fromCharCode(b)
  const expected = btoa(bin)
  // Constant-time-ish compare.
  if (expected.length !== header.length) return false
  let diff = 0
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ header.charCodeAt(i)
  return diff === 0
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const secret = Deno.env.get('AFTERSHIP_WEBHOOK_SECRET')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!secret || !supabaseUrl || !serviceKey) {
    return json({ error: 'tracking not configured' }, 503)
  }

  const raw = await req.text()
  if (!(await validSignature(secret, raw, req.headers.get('aftership-hmac-sha256')))) {
    return json({ error: 'invalid signature' }, 401)
  }

  let payload: any
  try { payload = JSON.parse(raw) } catch { return json({ error: 'bad request' }, 400) }

  // AfterShip posts { event, msg: <tracking object> } (or a v2025 `data`).
  const tracking = payload?.msg ?? payload?.data?.tracking ?? payload?.data ?? null
  if (!tracking) return json({ ok: true, updated: 0 }, 200)

  const trackingId: string | undefined = tracking.id
  const trackingNumber: string | undefined = tracking.tracking_number
  const tag: string = tracking.tag ?? 'Pending'
  const slug: string | undefined = tracking.slug

  // Normalize AfterShip checkpoints into our own timeline shape (newest first).
  const cps: any[] = Array.isArray(tracking.checkpoints) ? tracking.checkpoints : []
  const checkpoints = cps.map((c) => ({
    time: c?.checkpoint_time ?? c?.created_at ?? null,
    status: c?.subtag_message ?? c?.message ?? c?.tag ?? '',
    message: c?.message ?? '',
    location: [c?.location, c?.city, c?.state, c?.country_name].filter(Boolean).join(', ') || null,
    milestone: c?.tag ?? null,
  })).sort((a, b) => String(b.time).localeCompare(String(a.time)))

  const eta: string | null = tracking.expected_delivery || null
  const lastEventAt: string | null = checkpoints[0]?.time ?? null

  const patch: Record<string, unknown> = {
    live_status: liveStatus(tag),
    status: legacyStatus(tag),
    checkpoints,
    estimated_delivery: eta,
    last_event_at: lastEventAt,
    last_synced_at: new Date().toISOString(),
  }
  if (slug) patch.courier_code = slug

  const admin = createClient(supabaseUrl, serviceKey)
  let q = admin.from('packages').update(patch)
  q = trackingId ? q.eq('tracker_id', trackingId) : q.eq('tracking_number', trackingNumber ?? '')
  const { error, count } = await q.select('id', { count: 'exact' })
  if (error) return json({ error: 'db update failed', detail: error.message }, 500)

  return json({ ok: true, updated: count ?? 0 }, 200)
})

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}
