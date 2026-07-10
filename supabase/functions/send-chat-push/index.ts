import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ─── send-chat-push ──────────────────────────────────────────────────────────
// Delivers unpushed chat notifications to native iOS devices via APNs.
//
// Invocation: protected by CRON_SECRET (x-cron-secret header). Intended to be
// called by a Database Webhook / pg_cron after a chat message is inserted, or
// on a short schedule.
//
// Required secrets (until these are set, the function is a no-op 503):
//   APNS_KEY_ID        – the 10-char Key ID of the APNs auth key (.p8)
//   APNS_TEAM_ID       – Apple Developer Team ID
//   APNS_PRIVATE_KEY   – contents of the AuthKey_XXXX.p8 (PEM, with headers)
//   APNS_BUNDLE_ID     – app bundle id (e.g. com.prvio.app) -> apns-topic
//   CRON_SECRET        – shared secret to authorize this endpoint
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY – provided by the platform
// ──────────────────────────────────────────────────────────────────────────────

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret',
}

function b64url(bytes: Uint8Array): string {
  let bin = ''
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '')
  const bin = atob(b64)
  const buf = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i)
  return buf.buffer
}

async function makeApnsJwt(p8: string, keyId: string, teamId: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8(p8),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  )
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'ES256', kid: keyId })))
  const payload = b64url(new TextEncoder().encode(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) })))
  const signingInput = `${header}.${payload}`
  const sig = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput),
  )
  return `${signingInput}.${b64url(new Uint8Array(sig))}`
}

function apnsHost(environment: string): string {
  return environment === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com'
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const keyId = Deno.env.get('APNS_KEY_ID')
  const teamId = Deno.env.get('APNS_TEAM_ID')
  const p8 = Deno.env.get('APNS_PRIVATE_KEY')
  const bundleId = Deno.env.get('APNS_BUNDLE_ID')
  const cronSecret = Deno.env.get('CRON_SECRET')

  if (!keyId || !teamId || !p8 || !bundleId) {
    // Report WHICH secret names are visible (booleans only, never values) so a
    // missing/misnamed one is obvious from the response instead of a generic
    // "not configured".
    return new Response(JSON.stringify({
      error: 'APNs not configured',
      present: {
        APNS_KEY_ID: !!keyId,
        APNS_TEAM_ID: !!teamId,
        APNS_PRIVATE_KEY: !!p8,
        APNS_BUNDLE_ID: !!bundleId,
      },
    }), {
      status: 503,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  )

  // Two accepted callers: the legacy CRON_SECRET env, and the vault-held
  // webhook secret the notifications trigger sends (chat_push_secret() is
  // executable only with the service role, so anon clients can't read it).
  const provided = (req.headers.get('x-cron-secret') ?? '').trim()
  let authorized = !!cronSecret && provided === cronSecret.trim()
  if (!authorized && provided) {
    const { data: vaultSecret } = await admin.rpc('chat_push_secret')
    authorized = typeof vaultSecret === 'string' && provided === vaultSecret.trim()
  }
  if (!authorized) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }

  // Build the APNs JWT BEFORE claiming any rows. If the key is bad/rotated
  // this throws here — and because nothing has been stamped yet, the batch
  // stays unpushed and a later sweep retries it (instead of the old behaviour,
  // which claimed the rows first and then lost the whole batch on a JWT error).
  let jwt: string
  try {
    jwt = await makeApnsJwt(p8, keyId, teamId)
  } catch (e) {
    return new Response(JSON.stringify({ error: `APNs JWT: ${e instanceof Error ? e.message : e}` }), {
      status: 500,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }

  // Claim unpushed chat notifications atomically: the insert trigger can
  // fire this function several times in a burst, and stamping pushed_at
  // up-front means each row is sent by exactly one invocation.
  const { data: notes, error } = await admin
    .from('notifications')
    .update({ pushed_at: new Date().toISOString() })
    .eq('module', 'chat')
    .is('pushed_at', null)
    .select('id, user_id, title, body, resource_type, metadata')

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
  if (!notes || notes.length === 0) {
    return new Response(JSON.stringify({ sent: 0 }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }

  // Per-recipient unread chat count for the springboard badge, cached so a
  // burst to the same user is one query.
  const badgeCache = new Map<string, number>()
  async function unreadBadge(userId: string): Promise<number> {
    if (badgeCache.has(userId)) return badgeCache.get(userId)!
    const { count } = await admin
      .from('notifications')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId)
      .eq('module', 'chat')
      .eq('status', 'unread')
    const c = count ?? 0
    badgeCache.set(userId, c)
    return c
  }

  let sent = 0
  const deadTokens: string[] = []
  const retryIds: string[] = []

  for (const n of notes) {
    const { data: tokens } = await admin
      .from('device_tokens')
      .select('token, environment')
      .eq('user_id', n.user_id)
      .eq('platform', 'ios')

    if (!tokens || tokens.length === 0) continue // nothing to deliver, nothing to retry

    const badge = await unreadBadge(n.user_id)
    let anySuccess = false
    let anyTransient = false

    // Tapping the push must land in the right conversation: the notification
    // row's metadata (stamped by the DB triggers, migration 144) rides along
    // as a custom `chat` key, and thread-id groups banners per conversation.
    const meta = (n.metadata ?? {}) as Record<string, unknown>
    const chatInfo = {
      kind: (meta.kind as string) ?? (n.resource_type === 'direct_message' ? 'dm' : 'chat'),
      peer_user_id: (meta.peer_user_id as string) ?? null,
      peer_name: (meta.peer_name as string) ?? null,
      group_id: (meta.group_id as string) ?? null,
    }
    const threadId = chatInfo.peer_user_id ?? chatInfo.group_id ?? 'chat'

    for (const t of tokens) {
      const payload = {
        aps: {
          alert: { title: n.title ?? 'New message', body: n.body ?? '' },
          sound: 'default',
          badge,
          'thread-id': threadId,
        },
        chat: chatInfo,
      }
      try {
        const res = await fetch(`https://${apnsHost(t.environment)}/3/device/${t.token}`, {
          method: 'POST',
          headers: {
            authorization: `bearer ${jwt}`,
            'apns-topic': bundleId,
            'apns-push-type': 'alert',
          },
          body: JSON.stringify(payload),
        })
        if (res.ok) {
          sent++
          anySuccess = true
        } else {
          // 410 Unregistered / 400 BadDeviceToken are permanent — reap the
          // dead token so it stops wasting every future send. Everything else
          // (429/500/503, network) is transient → eligible for a retry.
          let reason = ''
          try { reason = ((await res.json())?.reason ?? '') as string } catch { /* no body */ }
          if (res.status === 410 || (res.status === 400 && reason === 'BadDeviceToken') || reason === 'Unregistered') {
            deadTokens.push(t.token)
          } else {
            anyTransient = true
          }
        }
      } catch (_e) {
        anyTransient = true
      }
    }

    // Had tokens, nothing landed, and the failures were transient → un-claim
    // so the next sweep tries again (bounded by the message eventually being
    // read, which stops mattering).
    if (!anySuccess && anyTransient) retryIds.push(n.id)
  }

  if (deadTokens.length > 0) {
    await admin.from('device_tokens').delete().in('token', deadTokens)
  }
  if (retryIds.length > 0) {
    await admin.from('notifications').update({ pushed_at: null }).in('id', retryIds)
  }

  return new Response(
    JSON.stringify({ sent, processed: notes.length, reaped: deadTokens.length, retry: retryIds.length }),
    { headers: { ...CORS, 'Content-Type': 'application/json' } },
  )
})
