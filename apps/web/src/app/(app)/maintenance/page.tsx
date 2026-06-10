import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Property, PropertyMember, MaintenanceTask } from '@/lib/supabase/types'
import { MaintenancePage } from '@/components/modules/maintenance/maintenance-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = {
  title: 'Maintenance',
}

export default async function MaintenanceRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: myMemberships } = await supabase
    .from('property_members')
    .select('*, properties(*)')
    .eq('user_id', user.id)
    .eq('status', 'active')
    .limit(1) as {
    data: (PropertyMember & { properties: Property | null })[] | null
    error: unknown
  }

  const property = myMemberships?.[0]?.properties ?? null

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Maintenance" />
        <NoPropertyState />
      </div>
    )
  }

  // Mark any past-due tasks as overdue before fetching (fires the notification trigger)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (supabase as any).rpc('mark_overdue_tasks', { p_property_id: property.id })

  const { data: tasks } = await supabase
    .from('maintenance_tasks')
    .select('*')
    .eq('property_id', property.id)
    .order('due_date', { ascending: true })
    .order('priority', { ascending: false }) as {
    data: MaintenanceTask[] | null
    error: unknown
  }

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <MaintenancePage property={property} tasks={tasks ?? []} />
    </div>
  )
}
