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
    const { to, name, propertyName, propertyId, role, inviterEmail, locale } = await req.json() as {
      to: string
      name?: string
      propertyName?: string
      propertyId?: string
      role?: string
      inviterEmail?: string
      locale?: string
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

    // Authorize the inviter BEFORE doing anything else. Inviting is always
    // property-scoped: a valid caller who is an active owner/partner of a
    // specific property. Enforcing this unconditionally (not only when a
    // propertyId happens to be present) is what stops an attacker from
    // omitting propertyId to reach generateLink/Resend and mint accounts or
    // send branded phishing under our verified domain.
    const jwt = req.headers.get('Authorization')?.replace('Bearer ', '')
    const { data: callerData } = jwt ? await admin.auth.getUser(jwt) : { data: { user: null } }
    const caller = callerData?.user ?? null

    if (!caller) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }
    if (!propertyId) {
      return new Response(JSON.stringify({ error: 'Missing required field: propertyId' }), {
        status: 400, headers: { ...CORS, 'Content-Type': 'application/json' },
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

    // Resolve the inviter's display name from their profile so the email reads
    // "Adi invited you..." instead of exposing their raw email. Also grab their
    // locale as a language fallback when the client doesn't send one.
    let profileName: string | undefined
    let profileLocale: string | undefined
    {
      const { data: prof } = await admin
        .from('profiles')
        .select('display_name, full_name, first_name, last_name, locale')
        .eq('id', caller.id)
        .maybeSingle()
      if (prof) {
        profileLocale = prof.locale ?? undefined
        const composed = [prof.first_name, prof.last_name].filter(Boolean).join(' ').trim()
        profileName = (prof.display_name?.trim() || prof.full_name?.trim() || composed) || undefined
      }
    }

    const dbRole = mapRole(role)

    async function grantMembership(userId?: string): Promise<void> {
      if (!propertyId || !userId || !caller) return
      await admin.from('property_members').upsert({
        property_id: propertyId,
        user_id: userId,
        role: dbRole,
        status: 'active',
        invited_by: caller.id,
      }, { onConflict: 'property_id,user_id' })
      await admin.from('family_members')
        .update({ user_id: userId })
        .eq('property_id', propertyId)
        .ilike('email', to)
        .is('user_id', null)
    }

    // Romanian is the app's primary language; fall back to the inviter's profile
    // locale, then Romanian, when the client doesn't tell us the recipient's.
    const lang: Lang = (locale ?? profileLocale ?? 'ro').toLowerCase().startsWith('en') ? 'en' : 'ro'
    const displayProperty = propertyName ?? (lang === 'ro' ? 'locuința ta' : 'your property')
    const displayInviter = profileName ?? inviterEmail ?? (lang === 'ro' ? 'Un utilizator PRVIO' : 'A PRVIO user')

    // Email delivery goes exclusively through Resend. generateLink creates the
    // auth user and returns the action link WITHOUT sending anything (so a
    // broken mailer can't block it); we send the branded email via Resend.
    if (!resendKey) {
      return new Response(JSON.stringify({
        error: 'Email sending is not configured (missing RESEND_API_KEY secret).',
      }), { status: 503, headers: { ...CORS, 'Content-Type': 'application/json' } })
    }

    // Audit trail for the Members hub: replace any previous invitation for this
    // email so created_at/expires_at reflect the LATEST send.
    if (propertyId && caller) {
      await admin.from('member_invitations')
        .delete()
        .eq('property_id', propertyId)
        .ilike('email', to)
      await admin.from('member_invitations').insert({
        property_id: propertyId,
        email: to,
        name: name ?? null,
        role: role ?? 'guest',
        invited_by: caller.id,
      })
    }

    let actionLink: string | undefined
    let invitedUserId: string | undefined
    const { data: inviteLink, error: inviteErr } = await admin.auth.admin.generateLink({
      type: 'invite',
      email: to,
      options: {
        redirectTo: 'prvio://',
        data: {
          property_id: propertyId,
          invited_role: role ?? 'member',
          invited_name: name,
          full_name: name ?? '',
          // Forces the strong-password setup screen on first sign-in.
          needs_password: true,
        },
      },
    })

    if (inviteErr) {
      const { data: mlData, error: mlError } = await admin.auth.admin.generateLink({
        type: 'magiclink',
        email: to,
        options: { redirectTo: 'prvio://' },
      })
      if (mlError) {
        return new Response(JSON.stringify({ error: mlError.message }), {
          status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
        })
      }
      actionLink = mlData.properties?.action_link
      invitedUserId = mlData.user?.id
    } else {
      actionLink = inviteLink.properties?.action_link
      invitedUserId = inviteLink.user?.id
    }

    await grantMembership(invitedUserId)

    if (!actionLink) {
      return new Response(JSON.stringify({ error: 'Could not generate an invite link.' }), {
        status: 500, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const emailError = await sendResendEmail(
      resendKey, to, displayProperty, displayInviter, role, actionLink, lang,
    )
    if (emailError) {
      return new Response(JSON.stringify({ error: `Email delivery failed: ${emailError}` }), {
        status: 502, headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({ sent: true, userId: invitedUserId }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})

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
    // A silent guest fallback once cost a PARTNER her family access (empty
    // chat, closed realtime channel — the has_family_access gate): an
    // unknown role string is a caller bug and must fail loudly, never
    // quietly grant the most restricted role.
    default: throw new Error(`send-invite-email: unknown role "${r}"`)
  }
}

type Lang = 'ro' | 'en'

// HTML-escape interpolated values so a name/property with < & " can't break the markup.
function esc(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}

// A human, localized label for a role. Falls back to the generic "member".
function roleLabelFor(role: string | undefined, lang: Lang): string {
  const r = (role ?? 'member').toLowerCase()
  const ro: Record<string, string> = { owner: 'Proprietar', partner: 'Partener', member: 'Membru', adult: 'Membru', family_adult: 'Membru', elderly: 'Membru', family_elderly: 'Membru', child: 'Copil', family_child: 'Copil', teen: 'Adolescent', family_teen: 'Adolescent', tenant: 'Chiriaș', worker: 'Muncitor', contractor: 'Muncitor', service_provider: 'Muncitor', guest: 'Prieten', friend: 'Prieten' }
  const en: Record<string, string> = { owner: 'Owner', partner: 'Partner', member: 'Member', adult: 'Member', family_adult: 'Member', elderly: 'Member', family_elderly: 'Member', child: 'Child', family_child: 'Child', teen: 'Teen', family_teen: 'Teen', tenant: 'Tenant', worker: 'Worker', contractor: 'Worker', service_provider: 'Worker', guest: 'Guest', friend: 'Guest' }
  const dict = lang === 'ro' ? ro : en
  return dict[r] ?? (lang === 'ro' ? 'Membru' : 'Member')
}

// Sends the branded invite via Resend. Returns null on success, or an error
// string the caller can surface. The sender is env-driven (INVITE_FROM) so the
// verified domain can change without a code deploy; defaults to the current one.
async function sendResendEmail(resendKey: string, to: string, displayProperty: string, displayInviter: string, role: string | undefined, inviteUrl: string, lang: Lang): Promise<string | null> {
  const from = Deno.env.get('INVITE_FROM') ?? 'PRVIO <invites@xparvu.com>'
  const roleLabel = roleLabelFor(role, lang)
  const inviter = esc(displayInviter)
  const property = esc(displayProperty)
  const roleText = esc(roleLabel)

  const t = lang === 'ro' ? {
    subject: `Ai fost invitat la ${displayProperty} pe PRVIO`,
    preheader: `${displayInviter} te-a invitat să te alături casei ${displayProperty}.`,
    tagline: 'Sistem de operare pentru locuință',
    heading: 'Ai fost invitat',
    bodyHtml: `<strong style="color:#eaf0fb;">${inviter}</strong> te-a invitat să te alături casei <strong style="color:#eaf0fb;">${property}</strong> pe PRVIO.`,
    roleIntro: 'Rol',
    cta: 'Acceptă invitația',
    fallbackIntro: 'Sau deschide acest link în browser:',
    expiry: 'Această invitație expiră în 7 zile.',
    ignore: 'Dacă nu te așteptai la acest email, îl poți ignora.',
  } : {
    subject: `You've been invited to ${displayProperty} on PRVIO`,
    preheader: `${displayInviter} invited you to join ${displayProperty}.`,
    tagline: 'Property Operating System',
    heading: "You've been invited",
    bodyHtml: `<strong style="color:#eaf0fb;">${inviter}</strong> has invited you to join <strong style="color:#eaf0fb;">${property}</strong> on PRVIO.`,
    roleIntro: 'Role',
    cta: 'Accept invitation',
    fallbackIntro: 'Or open this link in your browser:',
    expiry: 'This invitation expires in 7 days.',
    ignore: "If you weren't expecting this email, you can safely ignore it.",
  }

  const html = `<!DOCTYPE html>
<html lang="${lang}">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="dark"><meta name="supported-color-schemes" content="dark"></head>
<body style="margin:0; padding:0; background-color:#080b12; -webkit-font-smoothing:antialiased;">
  <div style="display:none; max-height:0; overflow:hidden; opacity:0; color:#080b12; font-size:1px; line-height:1px;">${esc(t.preheader)}&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;</div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#080b12;">
    <tr><td align="center" style="padding:40px 16px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px; margin:0 auto; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
        <tr><td align="center" style="padding-bottom:28px;">
          <table role="presentation" cellpadding="0" cellspacing="0"><tr>
            <td style="background-image:linear-gradient(135deg,#1e3a5f,#2d1b69); background-color:#233156; border-radius:18px; padding:15px 26px; text-align:center;">
              <div style="font-size:23px; font-weight:800; letter-spacing:0.14em; color:#ffffff;">PRVIO</div>
              <div style="font-size:9px; font-weight:600; letter-spacing:0.18em; text-transform:uppercase; color:#8ea6cc; margin-top:4px;">${esc(t.tagline)}</div>
            </td>
          </tr></table>
        </td></tr>
        <tr><td style="background-color:#111725; border:1px solid #1f2a40; border-radius:22px; padding:36px 32px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            <tr><td align="center"><div style="width:64px; height:64px; line-height:64px; border-radius:18px; background-image:linear-gradient(135deg,#2563eb,#7c3aed); background-color:#4f46e5; font-size:30px; text-align:center;">&#127968;</div></td></tr>
            <tr><td align="center" style="padding-top:22px;"><h1 style="margin:0; font-size:23px; line-height:1.25; font-weight:700; color:#f6f8fc;">${esc(t.heading)}</h1></td></tr>
            <tr><td align="center" style="padding-top:12px;"><p style="margin:0; font-size:15px; line-height:1.6; color:#9db0cd;">${t.bodyHtml}</p></td></tr>
            <tr><td align="center" style="padding-top:18px;"><span style="display:inline-block; font-size:11px; font-weight:700; letter-spacing:0.08em; text-transform:uppercase; color:#93c5fd; background-color:#17233d; border:1px solid #26375a; border-radius:999px; padding:6px 14px;">${esc(t.roleIntro)} &middot; ${roleText}</span></td></tr>
            <tr><td align="center" style="padding-top:28px;">
              <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 auto;"><tr>
                <td align="center" style="border-radius:14px; background-image:linear-gradient(135deg,#2563eb,#7c3aed); background-color:#5b4bdb;"><a href="${inviteUrl}" target="_blank" style="display:inline-block; padding:15px 32px; font-size:15px; font-weight:600; color:#ffffff; text-decoration:none; border-radius:14px;">${esc(t.cta)} &nbsp;&rarr;</a></td>
              </tr></table>
            </td></tr>
            <tr><td style="padding-top:26px;"><div style="border-top:1px solid #1c2740; padding-top:20px;"><p style="margin:0 0 8px; font-size:12px; color:#6f7f9c;">${esc(t.fallbackIntro)}</p><a href="${inviteUrl}" style="font-size:12px; color:#6ea8fe; text-decoration:none; word-break:break-all; line-height:1.5;">${inviteUrl}</a></div></td></tr>
          </table>
        </td></tr>
        <tr><td align="center" style="padding:22px 8px 0;"><p style="margin:0 0 6px; font-size:12px; color:#6b7a95;">${esc(t.expiry)}</p><p style="margin:0; font-size:11px; line-height:1.5; color:#4a5670;">${esc(t.ignore)}</p></td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`

  // Plain-text alternative — improves inbox placement and covers non-HTML clients.
  const text = [t.heading, '', `${displayInviter} -> ${displayProperty} (${roleLabel})`, '', t.fallbackIntro, inviteUrl, '', t.expiry, t.ignore].join('\n')

  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from, to: [to], subject: t.subject, html, text }),
    })
    if (!res.ok) {
      const body = await res.text()
      return `Resend ${res.status}: ${body}`
    }
    return null
  } catch (err) {
    return String(err)
  }
}
