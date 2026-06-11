import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { LeasePage } from '@/components/modules/tenant/lease-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Leases' }

export default async function LeasesRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Leases" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: leases } = await (supabase as any)
    .from('leases')
    .select('*')
    .eq('property_id', property.id)
    .order('created_at', { ascending: false })

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <LeasePage
        property={property}
        userId={user.id}
        initialLeases={leases ?? []}
      />
    </div>
  )
}
