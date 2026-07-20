import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Deletes a member's ACCOUNT (auth user) at the owner's request from the
// Members hub. Guard rails: caller must be an active owner/partner of the
// property, may not delete themselves, and may never delete an owner.
// profiles/family_members cascade from auth.users; property_members rows are
// removed explicitly (no FK to auth.users).

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const { memberId } = await req.json() as { memberId?: string }
    if (!memberId) return json({ error: 'Missing required field: memberId' }, 400)

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    )

    const jwt = req.headers.get('Authorization')?.replace('Bearer ', '')
    const { data: callerData } = jwt ? await admin.auth.getUser(jwt) : { data: { user: null } }
    const caller = callerData?.user ?? null
    if (!caller) return json({ error: 'Not authenticated' }, 401)

    const { data: target } = await admin
      .from('property_members')
      .select('id, property_id, user_id, role')
      .eq('id', memberId)
      .maybeSingle()
    if (!target) return json({ error: 'Member not found' }, 404)

    const { data: callerMembership } = await admin
      .from('property_members')
      .select('role')
      .eq('property_id', target.property_id)
      .eq('user_id', caller.id)
      .eq('status', 'active')
      .maybeSingle()
    if (!callerMembership || !['owner', 'partner'].includes(callerMembership.role)) {
      return json({ error: 'Not authorized' }, 403)
    }
    if (target.user_id === caller.id) return json({ error: 'You cannot delete your own account here' }, 400)
    if (target.role === 'owner') return json({ error: 'The owner account cannot be deleted' }, 400)

    // Remove all memberships first (no FK cascade), then the auth user —
    // profiles and family_members links cascade from auth.users.
    await admin.from('property_members').delete().eq('user_id', target.user_id)
    const { error: delErr } = await admin.auth.admin.deleteUser(target.user_id)
    if (delErr) return json({ error: delErr.message }, 500)

    return json({ deleted: true })
  } catch (err) {
    return json({ error: String(err) }, 500)
  }
})
