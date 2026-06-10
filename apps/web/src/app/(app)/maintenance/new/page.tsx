import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Property, PropertyMember } from '@/lib/supabase/types'
import { PageHeader } from '@/components/layout/page-header'
import { AddTaskForm } from '@/components/modules/maintenance/add-task-form'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'New Task' }

export default async function NewMaintenanceTaskPage() {
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
      <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
        <PageHeader title="New Task" backHref="/maintenance" />
        <NoPropertyState />
      </div>
    )
  }

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <PageHeader title="New Task" description={property.name} backHref="/maintenance" />
      <div className="px-4 py-4 md:px-6 md:py-6 max-w-xl">
        <AddTaskForm propertyId={property.id} userId={user.id} />
      </div>
    </div>
  )
}
