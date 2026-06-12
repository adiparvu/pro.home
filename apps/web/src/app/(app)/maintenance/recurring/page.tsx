import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'
import { RecurringTasksPage } from '@/components/modules/maintenance/recurring-tasks-page'

export const metadata: Metadata = { title: 'Recurring Tasks' }

export default async function RecurringTasksRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Recurring Tasks" backHref="/maintenance" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: templates } = await (supabase as any)
    .from('recurring_task_templates')
    .select('*')
    .eq('property_id', property.id)
    .order('created_at', { ascending: false })

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <RecurringTasksPage
        property={property}
        userId={user.id}
        initialTemplates={templates ?? []}
      />
    </div>
  )
}
