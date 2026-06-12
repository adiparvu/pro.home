import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { PropertyValuePage } from '@/components/modules/property/property-value-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Property Value' }

export default async function PropertyValueRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Property Value" backHref="/property" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: valuations } = await (supabase as any)
    .from('property_valuations')
    .select('*')
    .eq('property_id', property.id)
    .order('valuation_date', { ascending: true })

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PropertyValuePage
        property={property}
        userId={user.id}
        initialValuations={valuations ?? []}
      />
    </div>
  )
}
