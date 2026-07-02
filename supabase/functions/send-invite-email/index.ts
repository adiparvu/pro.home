import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }

  try {
    const { to, name, propertyName, propertyId, role, inviterEmail } = await req.json() as {
      to: string
      name?: string
      propertyName?: string
      propertyId?: string
      role?: string
      inviterEmail?: string
    }

    if (!to) {
      return new Response(JSON.stringify({ error: 'Missing required field: to' }), {
        status: 400,
        headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const resendKey = Deno.env.get('RESEND_API_KEY')

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    // ── Authorize the inviter ───────────────────────────────────────────────
    // Only an active owner/partner of the property may invite people into it.
    // Without this check any authenticated user could grant themselves access
    // to an arbitrary property by calling this function with its id.
    const jwt = req.headers.get('Authorization')?.replace('Bearer ', '')
    const { data: callerData } = jwt ? await admin.auth.getUser(jwt) : { data: { user: null } }
    const caller = callerData?.user ?? null

    if (propertyId) {
      if (!caller) {
        return new Response(JSON.stringify({ error: 'Not authenticated' }), {
          status: 401, headers: { ...CORS, 'Content-Type': 'application/json' },
        })
      }
      const { data: membership } = await admin
        .from('property_members')
        .select('role')
        .eq('property_id', propertyId)
        .eq('user_id', caller.id)
        .eq('status', 'active')
        .maybeSingle()
      if (!membership || !['owner', 'partner'].includes(membership.role)) {
        return new Response(JSON.stringify({ error: 'Not authorized to invite for this property' }), {
          status: 403, headers: { ...CORS, 'Content-Type': 'application/json' },
        })
      }
    }

    // Map the app's role strings onto the DB user_role enum (tolerant: unknown
    // roles fall back to the least-privileged 'guest').
    const dbRole = mapRole(role)

    // Grant membership for the invitee (new OR existing user). Uses the
    // service role so it bypasses RLS; runs after the auth user is resolved.
    async function grantMembership(userId?: string): Promise<void> {
      if (!propertyId || !userId || !caller) return
      await admin.from('property_members').upsert({
        property_id: propertyId,
        user_id: userId,
        role: dbRole,
        status: 'active',
        invited_by: caller.id,
      }, { onConflict: 'property_id,user_id' })
    }

    const displayProperty = propertyName ?? 'your property'
    const displayInviter = inviterEmail ?? 'A PRVIO user'
    const roleLabel = (role ?? 'member').replace(/_/g, ' ').replace(/\b\w/g, (c: string) => c.toUpperCase())

    // inviteUserByEmail sends a Supabase invitation email automatically
    // (uses Supabase's built-in email provider — no Resend required)
    const { data: inviteData, error: inviteError } = await admin.auth.admin.inviteUserByEmail(to, {
      redirectTo: 'prvio://',
      data: {
        property_id: propertyId,
        invited_role: role ?? 'member',
        invited_name: name,
      },
    })

    if (inviteError) {
      // User already exists — generate a magic link instead so they can access
      const { data: mlData, error: mlError } = await admin.auth.admin.generateLink({
        type: 'magiclink',
        email: to,
        options: { redirectTo: 'prvio://' },
      })
      if (mlError) {
        return new Response(JSON.stringify({ error: mlError.message }), {
          status: 500,
          headers: { ...CORS, 'Content-Type': 'application/json' },
        })
      }
      // Existing user — add them to the property now.
      await grantMembership(mlData.user?.id)
      // For existing users, send custom email if Resend is configured
      if (resendKey) {
        const inviteUrl = mlData.properties.action_link
        await sendResendEmail(resendKey, to, displayProperty, displayInviter, roleLabel, inviteUrl)
      }
      return new Response(JSON.stringify({ sent: true, note: 'existing_user_magic_link' }), {
        headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    // New user just created — add them to the property.
    await grantMembership(inviteData.user?.id)

    // For new users, Supabase already sent the invite email via inviteUserByEmail.
    // If Resend is configured, also send our custom branded email.
    if (resendKey) {
      const { data: linkData } = await admin.auth.admin.generateLink({
        type: 'invite',
        email: to,
        options: { redirectTo: 'prvio://' },
      })
      if (linkData?.properties?.action_link) {
        await sendResendEmail(resendKey, to, displayProperty, displayInviter, roleLabel, linkData.properties.action_link)
      }
    }

    return new Response(JSON.stringify({ sent: true, userId: inviteData.user?.id }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})

// Map the app's role labels onto the DB user_role enum. Tolerant by design:
// the app currently sends values like "member"/"child" that aren't enum
// members, so anything unrecognised falls back to the least-privileged guest.
function mapRole(r?: string): string {
  switch ((r ?? '').toLowerCase()) {
    case 'owner': return 'owner'
    case 'partner': return 'partner'
    case 'child': case 'family_child': return 'family_child'
    case 'teen': case 'family_teen': return 'family_teen'
    case 'adult': case 'member': case 'family_adult': return 'family_adult'
    case 'elderly': case 'family_elderly': return 'family_elderly'
    case 'tenant': return 'tenant'
    case 'worker': case 'contractor': case 'service_provider': return 'service_provider'
    case 'guest': case 'friend': return 'guest'
    default: return 'guest'
  }
}

async function sendResendEmail(
  resendKey: string,
  to: string,
  displayProperty: string,
  displayInviter: string,
  roleLabel: string,
  inviteUrl: string,
): Promise<void> {
  const html = `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', system-ui, sans-serif; background: #0a0e1a; color: #e2e8f0; margin: 0; padding: 40px 16px;">
  <div style="max-width: 480px; margin: 0 auto;">
    <div style="text-align: center; margin-bottom: 32px;">
      <div style="display: inline-block; background: linear-gradient(135deg, #1e3a5f, #2d1b69); border-radius: 20px; padding: 16px 24px;">
        <p style="font-size: 22px; font-weight: 800; margin: 0; background: linear-gradient(135deg, #60a5fa, #a78bfa); -webkit-background-clip: text; -webkit-text-fill-color: transparent;">PRVIO</p>
        <p style="font-size: 9px; color: #64748b; text-transform: uppercase; letter-spacing: 0.15em; margin: 2px 0 0;">Property Operating System</p>
      </div>
    </div>
    <div style="background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.08); border-radius: 24px; padding: 32px; margin-bottom: 24px;">
      <div style="font-size: 28px; margin-bottom: 16px;">🏠</div>
      <h1 style="font-size: 22px; font-weight: 700; margin: 0 0 8px; color: #f1f5f9;">You've been invited!</h1>
      <p style="font-size: 15px; color: #94a3b8; margin: 0 0 24px; line-height: 1.5;">
        <strong style="color: #e2e8f0;">${displayInviter}</strong> has invited you to join
        <strong style="color: #e2e8f0;">${displayProperty}</strong> as a <strong style="color: #e2e8f0;">${roleLabel}</strong> on PRVIO.
      </p>
      <a href="${inviteUrl}" style="display: block; text-align: center; background: linear-gradient(135deg, #2563eb, #7c3aed); color: white; text-decoration: none; font-size: 15px; font-weight: 600; padding: 16px 24px; border-radius: 14px; margin-bottom: 20px; letter-spacing: 0.01em;">
        Accept Invitation →
      </a>
    </div>
    <p style="font-size: 11px; color: #1e293b; text-align: center; margin: 0;">This invitation expires in 7 days.</p>
  </div>
</body>
</html>`

  await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: 'PRVIO <invites@prvio.app>',
      to: [to],
      subject: `You've been invited to ${displayProperty} on PRVIO`,
      html,
    }),
  })
}
