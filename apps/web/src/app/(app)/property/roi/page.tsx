import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { RoiPage } from '@/components/modules/property/roi-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'ROI Calculator' }

export default async function RoiRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="ROI Calculator" backHref="/property" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: valuations } = await (supabase as any)
    .from('property_valuations')
    .select('id, estimated_value, currency, valuation_date, created_at')
    .eq('property_id', property.id)
    .order('valuation_date', { ascending: true })

  const { data: expenses } = await supabase
    .from('financial_records')
    .select('id, title, amount, currency, category, created_at, date')
    .eq('property_id', property.id)
    .eq('type', 'expense')
    .order('date', { ascending: true })

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <RoiPage
        property={property}
        initialValuations={valuations ?? []}
        initialExpenses={expenses ?? []}
      />
    </div>
  )
}
