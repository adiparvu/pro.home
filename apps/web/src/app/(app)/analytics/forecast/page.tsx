import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { PropertyForecastPage } from '@/components/modules/analytics/property-forecast-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: '5-Year Forecast' }

export default async function ForecastRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="5-Year Forecast" backHref="/more" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: valuations } = await (supabase as any)
    .from('property_valuations')
    .select('id, estimated_value, currency, valuation_date')
    .eq('property_id', property.id)
    .order('valuation_date', { ascending: true })

  const twoYearsAgo = new Date()
  twoYearsAgo.setFullYear(twoYearsAgo.getFullYear() - 2)

  const { data: records } = await supabase
    .from('financial_records')
    .select('id, title, amount, currency, type, category, date')
    .eq('property_id', property.id)
    .gte('date', twoYearsAgo.toISOString().split('T')[0]!)
    .order('date', { ascending: true })

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PropertyForecastPage
        property={property}
        initialValuations={valuations ?? []}
        financialRecords={records ?? []}
      />
    </div>
  )
}
