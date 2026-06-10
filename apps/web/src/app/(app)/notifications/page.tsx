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
