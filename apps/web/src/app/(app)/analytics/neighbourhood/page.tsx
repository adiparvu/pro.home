import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { NeighbourhoodPage } from '@/components/modules/analytics/neighbourhood-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Neighbourhood Benchmarks' }

export default async function NeighbourhoodRoute() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Neighbourhood Benchmarks" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sb = supabase as any

  const twelveMonthsAgo = new Date()
  twelveMonthsAgo.setFullYear(twelveMonthsAgo.getFullYear() - 1)

  const [benchmarksRes, financialRes, leasesRes] = await Promise.all([
    sb
      .from('neighbourhood_benchmarks')
      .select('id, property_id, metric, value, unit, source, recorded_date, notes, created_by, created_at')
      .eq('property_id', property.id)
      .order('metric', { ascending: true })
      .order('recorded_date', { ascending: false }),

    supabase
      .from('financial_records')
      .select('amount')
      .eq('property_id', property.id)
      .eq('type', 'expense')
      .gte('date', twelveMonthsAgo.toISOString().split('T')[0]!),

    sb
      .from('leases')
      .select('monthly_rent, status')
      .eq('property_id', property.id)
      .eq('status', 'active'),
  ])

  const expenses: { amount: number }[] = financialRes.data ?? []
  const totalExpenses = expenses.reduce((s, e) => s + e.amount, 0)
  const avgMonthly = expenses.length > 0 ? totalExpenses / 12 : 0

  const leases: { monthly_rent: number; status: string }[] = leasesRes.data ?? []
  const totalRent = leases.reduce((s, l) => s + l.monthly_rent, 0)

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <NeighbourhoodPage
        property={property}
        initialBenchmarks={benchmarksRes.data ?? []}
        monthlyExpenses={avgMonthly}
        monthlyRent={totalRent}
      />
    </div>
  )
}
