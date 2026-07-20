import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ─── track-register ───────────────────────────────────────────────────────────
// Registers a delivery's tracking number with the tracking aggregator (Ship24)
// so it starts pushing status events to `track-webhook`. Called by the app when
// a package with a tracking number is created or edited.
//
// Flow:
//   1. Verify the caller's JWT and that they can read the package (RLS).
//   2. POST the tracking number to Ship24 -> get a trackerId.
//   3. Store it on the package (service role).
//
// This is one of only TWO files that know the aggregator's API — the app and DB
// are provider-agnostic, so swapping aggregators means rewriting just these two.
//
// Required secrets (no-op 503 until set):
//   SHIP24_API_KEY                             – Ship24 API key (Bearer)
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY   – provided by the platform
// ──────────────────────────────────────────────────────────────────────────────

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SHIP24_BASE = 'https://api.ship24.com/public/v1'

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const apiKey = Deno.env.get('SHIP24_API_KEY')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!apiKey || !supabaseUrl || !serviceKey) {
    return json({ error: 'tracking not configured' }, 503)
  }

  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader.startsWith('Bearer ')) return json({ error: 'unauthorized' }, 401)

  let body: {
    package_id?: string
    trackingNumber?: string
    courierCode?: string
    destinationCountryCode?: string
    originCountryCode?: string
  }
  try { body = await req.json() } catch { return json({ error: 'bad request' }, 400) }

  const { package_id, trackingNumber } = body
  if (!package_id || !trackingNumber) return json({ error: 'package_id and trackingNumber required' }, 400)

  // RLS-scoped read with the caller's token: only succeeds if they may see it.
  const asUser = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY') ?? serviceKey, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: pkg, error: readErr } = await asUser
    .from('packages').select('id').eq('id', package_id).maybeSingle()
  if (readErr || !pkg) return json({ error: 'forbidden' }, 403)

  // Register the tracker with Ship24. Courier is auto-detected from the number
  // when courierCode is omitted.
  let trackerId: string | null = null
  try {
    const res = await fetch(`${SHIP24_BASE}/trackers`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        trackingNumber,
        courierCode: body.courierCode ? [body.courierCode] : undefined,
        destinationCountryCode: body.destinationCountryCode,
        originCountryCode: body.originCountryCode,
      }),
    })
    const payload = await res.json().catch(() => ({}))
    if (!res.ok) return json({ error: 'aggregator error', detail: payload }, 502)
    trackerId = payload?.data?.tracker?.trackerId ?? null
  } catch (e) {
    return json({ error: 'aggregator unreachable', detail: String(e) }, 502)
  }
  if (!trackerId) return json({ error: 'no trackerId returned' }, 502)

  // Persist (service role bypasses RLS; access already checked above).
  const admin = createClient(supabaseUrl, serviceKey)
  const { error: updErr } = await admin
    .from('packages')
    .update({
      tracker_id: trackerId,
      courier_code: body.courierCode ?? null,
      live_status: 'pending',
      tracking_enabled: true,
      last_synced_at: new Date().toISOString(),
    })
    .eq('id', package_id)
  if (updErr) return json({ error: 'db update failed', detail: updErr.message }, 500)

  return json({ trackerId }, 200)
})

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}
