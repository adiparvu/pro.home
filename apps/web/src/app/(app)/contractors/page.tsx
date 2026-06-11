import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'
import { ContractorsPage } from '@/components/modules/contractors/contractors-page'

export const metadata: Metadata = { title: 'Contractors' }

export default async function ContractorsRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Contractors" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: contractors } = await (supabase as any)
    .from('contractors')
    .select('*')
    .eq('property_id', property.id)
    .order('is_preferred', { ascending: false })
    .order('name')

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <ContractorsPage
        property={property}
        userId={user.id}
        initialContractors={contractors ?? []}
      />
    </div>
  )
}
