import { type Metadata } from 'next'
import { createClient } from '@/lib/supabase/server'
import type { Property } from '@/lib/supabase/types'
import { DashboardHeader } from '@/components/modules/dashboard/dashboard-header'
import { HealthHeroCard } from '@/components/modules/dashboard/health-hero-card'
import { DashboardWidgetGrid } from '@/components/modules/dashboard/widget-grid'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = {
  title: 'Dashboard',
}

export default async function DashboardPage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) return null

  // Fetch user's properties
  const { data: properties } = await supabase
    .from('properties')
    .select('*, property_members!inner(role, status)')
    .eq('property_members.user_id', user.id)
    .eq('property_members.status', 'active')
    .eq('is_active', true)
    .order('created_at', { ascending: false }) as { data: Property[] | null; error: unknown }

  if (!properties || properties.length === 0) {
    return (
      <div className="flex flex-1 flex-col">
        <DashboardHeader user={user} />
        <NoPropertyState />
      </div>
    )
  }

  const activeProperty = properties[0]!

  // Fetch upcoming tasks count
  const { count: upcomingTasksCount } = await supabase
    .from('maintenance_tasks')
    .select('*', { count: 'exact', head: true })
    .eq('property_id', activeProperty.id)
    .in('status', ['pending', 'in_progress'])

  // Fetch unread notifications count
  const { count: unreadNotifications } = await supabase
    .from('notifications')
    .select('*', { count: 'exact', head: true })
    .eq('user_id', user.id)
    .eq('status', 'unread')

  // Fetch inventory count
  const { count: inventoryCount } = await supabase
    .from('inventory_items')
    .select('*', { count: 'exact', head: true })
    .eq('property_id', activeProperty.id)

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <DashboardHeader
        user={user}
        notificationCount={unreadNotifications ?? 0}
        properties={properties}
        activeProperty={activeProperty}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Health Hero Card */}
        <HealthHeroCard property={activeProperty} />

        {/* Widget Grid */}
        <DashboardWidgetGrid
          property={activeProperty}
          upcomingTasksCount={upcomingTasksCount ?? 0}
          inventoryCount={inventoryCount ?? 0}
        />
      </div>
    </div>
  )
}
