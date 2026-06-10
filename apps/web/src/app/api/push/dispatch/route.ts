import { NextResponse } from 'next/server'
import webpush from 'web-push'
import { createClient as createServerClient } from '@/lib/supabase/server'
import { createClient as createAdminClient } from '@supabase/supabase-js'

export const dynamic = 'force-dynamic'

interface PushRow {
  id: string
  user_id: string
  title: string
  body: string | null
  action_url: string | null
}

interface SubRow {
  user_id: string
  endpoint: string
  p256dh: string
  auth: string
}

function vapidConfigured() {
  return Boolean(process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY && process.env.VAPID_PRIVATE_KEY)
}

/**
 * Delivers unpushed notifications as Web Push messages.
 *
 * Two modes:
 * - Cron: `x-cron-secret` header matching CRON_SECRET + SUPABASE_SERVICE_ROLE_KEY
 *   set → dispatches for all users (intended to be hit by a scheduler after
 *   deployment).
 * - Session: an authenticated user → dispatches their own pending
 *   notifications only (RLS-scoped; useful for testing).
 */
export async function POST(request: Request) {
  if (!vapidConfigured()) {
    return NextResponse.json({ error: 'VAPID keys not configured' }, { status: 503 })
  }

  webpush.setVapidDetails(
    process.env.VAPID_SUBJECT ?? 'mailto:admin@prvhouse.app',
    process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY!,
    process.env.VAPID_PRIVATE_KEY!
  )

  const cronSecret = process.env.CRON_SECRET
  const isCron =
    cronSecret &&
    request.headers.get('x-cron-secret') === cronSecret &&
    process.env.SUPABASE_SERVICE_ROLE_KEY

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let db: any
  let scopeUserId: string | null = null

  if (isCron) {
    db = createAdminClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!
    )
  } else {
    const supabase = await createServerClient()
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    db = supabase
    scopeUserId = user.id
  }

  let notifQuery = db
    .from('notifications')
    .select('id, user_id, title, body, action_url')
    .is('pushed_at', null)
    .gt('created_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
    .limit(200)
  if (scopeUserId) notifQuery = notifQuery.eq('user_id', scopeUserId)
  const { data: pending } = (await notifQuery) as { data: PushRow[] | null }

  if (!pending || pending.length === 0) {
    return NextResponse.json({ sent: 0 })
  }

  const userIds = [...new Set(pending.map((n) => n.user_id))]
  const { data: subs } = (await db
    .from('push_subscriptions')
    .select('user_id, endpoint, p256dh, auth')
    .in('user_id', userIds)) as { data: SubRow[] | null }

  const subsByUser = new Map<string, SubRow[]>()
  for (const sub of subs ?? []) {
    if (!subsByUser.has(sub.user_id)) subsByUser.set(sub.user_id, [])
    subsByUser.get(sub.user_id)!.push(sub)
  }

  let sent = 0
  const staleEndpoints: string[] = []

  for (const notification of pending) {
    const userSubs = subsByUser.get(notification.user_id) ?? []
    for (const sub of userSubs) {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          JSON.stringify({
            title: notification.title,
            body: notification.body ?? '',
            url: notification.action_url ?? '/notifications',
          })
        )
        sent++
      } catch (err) {
        const status = (err as { statusCode?: number }).statusCode
        if (status === 404 || status === 410) staleEndpoints.push(sub.endpoint)
      }
    }
  }

  // Mark everything processed (even users without subscriptions, so we
  // don't rescan the same rows forever)
  await db
    .from('notifications')
    .update({ pushed_at: new Date().toISOString() })
    .in('id', pending.map((n) => n.id))

  if (staleEndpoints.length > 0) {
    await db.from('push_subscriptions').delete().in('endpoint', staleEndpoints)
  }

  return NextResponse.json({ sent, processed: pending.length, staleRemoved: staleEndpoints.length })
}
