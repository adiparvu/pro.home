import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Cross-app inbox: external services POST { token, text, sender? } and the
// message lands in the property's group chat (realtime pushes it to devices).
// Auth is a secret token (verify_jwt is off — Shortcuts, Zapier or a webhook
// can't carry a Supabase JWT). Two kinds of token are accepted:
//   1. the property's shared channel token (cross_app_channels)
//   2. a per-integration token (custom_integrations) — individually named,
//      toggleable and revocable; last_used_at is stamped on every delivery.
// The property's channel row is the master switch: disabling it silences the
// shared token AND every custom integration for that property.
//
// Security posture (Batch 5):
//   • Invalid, unknown, disabled and muted tokens all return the SAME 401 so
//     the endpoint can't be used as an oracle to distinguish real-but-disabled
//     tokens from garbage.
//   • Per-property flood guard: at most RATE_MAX external messages per
//     RATE_WINDOW_S, counted from the messages already stored, so a leaked
//     token can't be used to spam a house chat unbounded.

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const RATE_MAX = 30           // external messages …
const RATE_WINDOW_S = 60      // … per property per minute

function json(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return json(405, { error: 'POST only' })

  try {
    const { token, text, sender } = await req.json() as {
      token?: string; text?: string; sender?: string
    }
    // Uniform 401 for anything token-shaped-but-unusable (see note above).
    const unauthorized = json(401, { error: 'Unauthorized' })
    if (!token || !/^[0-9a-f-]{36}$/i.test(token)) return unauthorized
    const body = (text ?? '').trim()
    if (!body) return json(400, { error: 'Missing text' })
    if (body.length > 4000) return json(400, { error: 'Text too long (max 4000)' })

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    )

    let propertyId: string | null = null
    let integrationName: string | null = null
    let integrationId: string | null = null

    const { data: channel } = await admin
      .from('cross_app_channels')
      .select('property_id, enabled')
      .eq('token', token)
      .maybeSingle()

    if (channel) {
      if (!channel.enabled) return unauthorized
      propertyId = channel.property_id
    } else {
      const { data: integration } = await admin
        .from('custom_integrations')
        .select('id, property_id, name, enabled')
        .eq('token', token)
        .maybeSingle()
      if (!integration || !integration.enabled) return unauthorized

      const { data: master } = await admin
        .from('cross_app_channels')
        .select('enabled')
        .eq('property_id', integration.property_id)
        .maybeSingle()
      if (master && !master.enabled) return unauthorized

      propertyId = integration.property_id
      integrationName = integration.name
      integrationId = integration.id
    }

    // Flood guard: count external messages already stored in the window.
    const since = new Date(Date.now() - RATE_WINDOW_S * 1000).toISOString()
    const { count } = await admin
      .from('messages')
      .select('id', { count: 'exact', head: true })
      .eq('property_id', propertyId)
      .is('sender_id', null)
      .gte('created_at', since)
    if ((count ?? 0) >= RATE_MAX) {
      return json(429, { error: 'Rate limit exceeded. Try again shortly.' })
    }

    // Stamp last_used_at only once we've decided to accept the message.
    if (integrationId) {
      await admin
        .from('custom_integrations')
        .update({ last_used_at: new Date().toISOString() })
        .eq('id', integrationId)
    }

    const senderName = (sender ?? '').trim().slice(0, 60) || integrationName?.slice(0, 60)
    const { error } = await admin.from('messages').insert({
      property_id: propertyId,
      sender_id: null,
      sender_name: senderName ? `⥂ ${senderName}` : '⥂ App externă',
      body,
      mentioned_ids: [],
    })
    // Don't echo the raw DB error back to an unauthenticated caller.
    if (error) {
      console.error('cross-app-inbox insert error:', error.message)
      return json(500, { error: 'Could not deliver the message.' })
    }

    return json(200, { ok: true })
  } catch (err) {
    console.error('cross-app-inbox error:', String(err))
    return json(500, { error: 'Internal error.' })
  }
})
