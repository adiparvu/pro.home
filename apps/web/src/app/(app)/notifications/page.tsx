import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Notification } from '@/lib/supabase/types'
import { NotificationsPage } from '@/components/modules/notifications/notifications-page'

export const metadata: Metadata = { title: 'Notifications' }

export default async function NotificationsRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  // Surface all on-demand notifications on each page load (24h dedup in DB)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await Promise.all([
    (supabase as any).rpc('create_doc_expiry_notifications', { p_user_id: user.id }),
    (supabase as any).rpc('create_recall_notifications', { p_user_id: user.id }),
    (supabase as any).rpc('create_overdue_task_notifications', { p_user_id: user.id }),
    (supabase as any).rpc('create_garden_watering_notifications', { p_user_id: user.id }),
    (supabase as any).rpc('create_warranty_expiry_notifications', { p_user_id: user.id }),
  ])

  const { data: notifications } = await supabase
    .from('notifications')
    .select('*')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
    .limit(50) as { data: Notification[] | null; error: unknown }

  return (
    <div className="flex flex-1 flex-col">
      <NotificationsPage notifications={notifications ?? []} userId={user.id} />
    </div>
  )
}
