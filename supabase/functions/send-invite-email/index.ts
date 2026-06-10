import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }

  try {
    const { to, inviterEmail, propertyName, role, inviteUrl } = await req.json() as {
      to: string
      inviterEmail: string
      propertyName: string
      role: string
      inviteUrl: string
    }

    const resendKey = Deno.env.get('RESEND_API_KEY')
    if (!resendKey) {
      return new Response(JSON.stringify({ error: 'RESEND_API_KEY not configured' }), {
        status: 500,
        headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    const roleLabel = role.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())

    const html = `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: system-ui, sans-serif; background: #0d1420; color: #e2e8f0; margin: 0; padding: 40px 16px;">
  <div style="max-width: 480px; margin: 0 auto; background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.1); border-radius: 24px; padding: 32px;">
    <p style="font-size: 24px; font-weight: 800; margin: 0 0 4px; background: linear-gradient(135deg, #60a5fa, #a78bfa); -webkit-background-clip: text; -webkit-text-fill-color: transparent;">PRV HOUSE</p>
    <p style="font-size: 11px; color: #64748b; text-transform: uppercase; letter-spacing: 0.1em; margin: 0 0 32px;">Property Operating System</p>

    <p style="font-size: 16px; font-weight: 600; margin: 0 0 8px;">You've been invited!</p>
    <p style="font-size: 14px; color: #94a3b8; margin: 0 0 24px;">
      <strong style="color: #e2e8f0;">${inviterEmail}</strong> has invited you to join
      <strong style="color: #e2e8f0;">${propertyName}</strong> as a <strong style="color: #e2e8f0;">${roleLabel}</strong>.
    </p>

    <a href="${inviteUrl}"
      style="display: block; text-align: center; background: hsl(210,75%,42%); color: white; text-decoration: none; font-size: 14px; font-weight: 600; padding: 14px 24px; border-radius: 14px; margin-bottom: 24px;">
      Accept Invitation
    </a>

    <p style="font-size: 12px; color: #475569; margin: 0;">
      Or copy this link: <a href="${inviteUrl}" style="color: #60a5fa;">${inviteUrl}</a>
    </p>
    <p style="font-size: 11px; color: #334155; margin: 16px 0 0;">This invitation expires in 7 days.</p>
  </div>
</body>
</html>`

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${resendKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'PRV HOUSE <invites@prvhouse.app>',
        to: [to],
        subject: `You've been invited to ${propertyName} on PRV HOUSE`,
        html,
      }),
    })

    if (!res.ok) {
      const err = await res.text()
      return new Response(JSON.stringify({ error: err }), {
        status: 500,
        headers: { ...CORS, 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({ sent: true }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})
