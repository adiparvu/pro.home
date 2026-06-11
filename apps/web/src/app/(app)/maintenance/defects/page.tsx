import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'
import { DefectLogPage } from '@/components/modules/maintenance/defect-log-page'

export const metadata: Metadata = { title: 'Defect Log' }

export default async function DefectLogRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Defect Log" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: defects } = await (supabase as any)
    .from('defect_logs')
    .select('*')
    .eq('property_id', property.id)
    .order('created_at', { ascending: false })

  const { data: rooms } = await supabase
    .from('rooms')
    .select('id, name')
    .eq('property_id', property.id)

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <DefectLogPage
        property={property}
        userId={user.id}
        initialDefects={defects ?? []}
        rooms={rooms ?? []}
      />
    </div>
  )
}
