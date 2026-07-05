import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ─── track-webhook ────────────────────────────────────────────────────────────
// Receives status events from Ship24 and writes a NORMALIZED view of them onto
// `packages`. This is the ONLY place in the system that knows Ship24's payload
// shape — the iOS app and the database schema are provider-agnostic, so
// switching aggregators later means rewriting just this file (and track-register),
// with zero client or schema changes.
//
// Security: Ship24 is configured to call this URL with a shared secret in the
// query string (?secret=…) matching SHIP24_WEBHOOK_SECRET.
//
// Required secrets (no-op 503 until set):
//   SHIP24_WEBHOOK_SECRET                      – shared secret in the webhook URL
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY   – provided by the platform
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

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const secret = Deno.env.get('SHIP24_WEBHOOK_SECRET')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!secret || !supabaseUrl || !serviceKey) {
    return json({ error: 'tracking not configured' }, 503)
  }

  // Shared-secret gate (Ship24 webhook URL is configured with ?secret=…).
  const url = new URL(req.url)
  if (url.searchParams.get('secret') !== secret) return json({ error: 'unauthorized' }, 401)

  let payload: any
  try { payload = await req.json() } catch { return json({ error: 'bad request' }, 400) }

  // Ship24 posts { trackings: [ { tracker, shipment, events } ] }. Be defensive
  // about the envelope so provider quirks don't drop events.
  const trackings: any[] = payload?.trackings ?? payload?.data?.trackings ?? []
  if (!Array.isArray(trackings) || trackings.length === 0) return json({ ok: true, updated: 0 }, 200)

  const admin = createClient(supabaseUrl, serviceKey)
  let updated = 0

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
    const { error, count } = await q.select('id', { count: 'exact' })
    if (!error) updated += count ?? 0
  }

  return json({ ok: true, updated }, 200)
})

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}
