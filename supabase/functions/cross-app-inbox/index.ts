import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Cross-app inbox: external services POST { token, text, sender? } and the
// message lands in the property's group chat (realtime pushes it to devices).
// Auth is the per-property secret token (verify_jwt is off — Shortcuts, Zapier
// or a webhook can't carry a Supabase JWT). The channel can be disabled or the
// token rotated at any time from Settings -> Cross-app messaging.

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

    const { data: channel } = await admin
      .from('cross_app_channels')
      .select('property_id, enabled')
      .eq('token', token)
      .maybeSingle()
    if (!channel) return bad(401, 'Invalid token')
    if (!channel.enabled) return bad(403, 'Channel disabled')

    const senderName = (sender ?? '').trim().slice(0, 60)
    const { error } = await admin.from('messages').insert({
      property_id: channel.property_id,
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
