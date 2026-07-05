import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ─── track-register ───────────────────────────────────────────────────────────
// Registers a delivery's tracking number with the tracking aggregator
// (AfterShip) so it starts pushing status events to `track-webhook`. Called by
// the app when a package with a tracking number is created or edited.
//
// Flow:
//   1. Verify the caller's JWT and that they can read the package (RLS).
//   2. POST the tracking number to AfterShip -> get a tracking id + courier slug.
//   3. Store them on the package (service role).
//
// This is one of only TWO files that know the aggregator's API — the app and DB
// are provider-agnostic, so swapping aggregators means rewriting just these two.
//
// Required secrets (no-op 503 until set):
//   AFTERSHIP_API_KEY                          – AfterShip API key
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY   – provided by the platform
// ──────────────────────────────────────────────────────────────────────────────

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const AFTERSHIP_BASE = 'https://api.aftership.com/v4'

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const apiKey = Deno.env.get('AFTERSHIP_API_KEY')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!apiKey || !supabaseUrl || !serviceKey) {
    return json({ error: 'tracking not configured' }, 503)
  }

  const authHeader = req.headers.get('Authorization') ?? ''
  if (!authHeader.startsWith('Bearer ')) return json({ error: 'unauthorized' }, 401)

  let body: { package_id?: string; trackingNumber?: string; courierCode?: string }
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

  // Create the tracking in AfterShip. Courier slug is optional — AfterShip
  // auto-detects it from the number when omitted.
  let trackingId: string | null = null
  let slug: string | null = null
  try {
    const res = await fetch(`${AFTERSHIP_BASE}/trackings`, {
      method: 'POST',
      headers: { 'aftership-api-key': apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        tracking: {
          tracking_number: trackingNumber,
          slug: body.courierCode || undefined,
        },
      }),
    })
    const payload = await res.json().catch(() => ({}))
    if (res.ok) {
      trackingId = payload?.data?.tracking?.id ?? null
      slug = payload?.data?.tracking?.slug ?? null
    } else if (res.status === 409) {
      // Already tracked in AfterShip — fine. The webhook still matches this
      // parcel by tracking number, so we just mark it pending.
      slug = payload?.data?.tracking?.slug ?? body.courierCode ?? null
    } else {
      return json({ error: 'aggregator error', detail: payload }, 502)
    }
  } catch (e) {
    return json({ error: 'aggregator unreachable', detail: String(e) }, 502)
  }

  // Persist (service role bypasses RLS; access already checked above).
  const admin = createClient(supabaseUrl, serviceKey)
  const { error: updErr } = await admin
    .from('packages')
    .update({
      tracker_id: trackingId,
      courier_code: slug,
      live_status: 'pending',
      tracking_enabled: true,
      last_synced_at: new Date().toISOString(),
    })
    .eq('id', package_id)
  if (updErr) return json({ error: 'db update failed', detail: updErr.message }, 500)

  return json({ trackerId: trackingId, courier: slug }, 200)
})

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}
