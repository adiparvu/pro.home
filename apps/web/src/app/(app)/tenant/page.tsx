import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { TenantPortalPage } from '@/components/modules/tenant/tenant-portal-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Tenant Portal' }

export default async function TenantPortalRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Tenant Portal" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: member } = await ((supabase as any)
    .from('property_members')
    .select('role, joined_at, nickname')
    .eq('property_id', property.id)
    .eq('user_id', user.id)
    .eq('status', 'active')
    .maybeSingle()) as { data: { role: string; joined_at: string; nickname: string | null } | null }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: openTasks } = await (supabase as any)
    .from('maintenance_tasks')
    .select('id, title, status, priority, due_date, category')
    .eq('property_id', property.id)
    .in('status', ['pending', 'in_progress', 'overdue'])
    .order('due_date', { ascending: true })
    .limit(20)

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: documents } = await (supabase as any)
    .from('documents')
    .select('id, name, category, file_url, expires_at')
    .eq('property_id', property.id)
    .in('category', ['legal', 'insurance', 'utility'])
    .order('created_at', { ascending: false })
    .limit(20)

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <TenantPortalPage
        property={property}
        userId={user.id}
        memberRole={member?.role ?? 'tenant'}
        openTasks={openTasks ?? []}
        sharedDocuments={documents ?? []}
      />
    </div>
  )
}
