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

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function bad(status: number, error: string): Response {
  return new Response(JSON.stringify({ error }), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return bad(405, 'POST only')

  try {
    const { token, text, sender } = await req.json() as {
      token?: string; text?: string; sender?: string
    }
    if (!token || !/^[0-9a-f-]{36}$/i.test(token)) return bad(401, 'Invalid token')
    const body = (text ?? '').trim()
    if (!body) return bad(400, 'Missing text')
    if (body.length > 4000) return bad(400, 'Text too long (max 4000)')

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    )

    let propertyId: string | null = null
    let integrationName: string | null = null

    const { data: channel } = await admin
      .from('cross_app_channels')
      .select('property_id, enabled')
      .eq('token', token)
      .maybeSingle()

    if (channel) {
      if (!channel.enabled) return bad(403, 'Channel disabled')
      propertyId = channel.property_id
    } else {
      const { data: integration } = await admin
        .from('custom_integrations')
        .select('id, property_id, name, enabled')
        .eq('token', token)
        .maybeSingle()
      if (!integration) return bad(401, 'Invalid token')
      if (!integration.enabled) return bad(403, 'Integration disabled')

      const { data: master } = await admin
        .from('cross_app_channels')
        .select('enabled')
        .eq('property_id', integration.property_id)
        .maybeSingle()
      if (master && !master.enabled) return bad(403, 'Channel disabled')

      propertyId = integration.property_id
      integrationName = integration.name
      await admin
        .from('custom_integrations')
        .update({ last_used_at: new Date().toISOString() })
        .eq('id', integration.id)
    }

    const senderName = (sender ?? '').trim().slice(0, 60) || integrationName?.slice(0, 60)
    const { error } = await admin.from('messages').insert({
      property_id: propertyId,
      sender_id: null,
      sender_name: senderName ? `⥂ ${senderName}` : '⥂ App externă',
      body,
      mentioned_ids: [],
    })
    if (error) return bad(500, error.message)

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    return bad(500, String(err))
  }
})
