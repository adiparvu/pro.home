import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { YieldPage } from '@/components/modules/analytics/yield-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Rent Yield Calculator' }

export default async function YieldRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Rent Yield" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: leases } = await (supabase as any)
    .from('leases')
    .select('id, monthly_rent, currency, status, start_date, end_date')
    .eq('property_id', property.id)

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: valuations } = await (supabase as any)
    .from('property_valuations')
    .select('id, estimated_value, currency, valuation_date')
    .eq('property_id', property.id)
    .order('valuation_date', { ascending: false })
    .limit(1)

  const twelveMonthsAgo = new Date()
  twelveMonthsAgo.setFullYear(twelveMonthsAgo.getFullYear() - 1)

  const { data: expenses } = await supabase
    .from('financial_records')
    .select('id, title, amount, currency, category, date')
    .eq('property_id', property.id)
    .eq('type', 'expense')
    .gte('date', twelveMonthsAgo.toISOString().split('T')[0]!)

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <YieldPage
        property={property}
        initialLeases={leases ?? []}
        latestValuation={valuations?.[0] ?? null}
        annualExpenses={expenses ?? []}
      />
    </div>
  )
}
