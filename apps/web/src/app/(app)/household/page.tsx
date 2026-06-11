import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { HouseholdPage } from '@/components/modules/household/household-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Household' }

export default async function HouseholdRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Household" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: lists } = await (supabase as any)
    .from('household_lists')
    .select('*, household_list_items(*)')
    .eq('property_id', property.id)
    .order('name')

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <HouseholdPage
        property={property}
        userId={user.id}
        initialLists={lists ?? []}
      />
    </div>
  )
}
