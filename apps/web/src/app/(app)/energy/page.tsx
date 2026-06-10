import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/layout/page-header'
import { EnergyOverview } from '@/components/modules/energy/energy-overview'
import type { Property, FinancialRecord, EnergyReading } from '@/lib/supabase/types'

export const metadata: Metadata = { title: 'Energy' }

export default async function EnergyPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: property } = await supabase
    .from('properties')
    .select('*, property_members!inner(role, status)')
    .eq('property_members.user_id', user.id)
    .eq('property_members.status', 'active')
    .eq('is_active', true)
    .order('created_at', { ascending: false })
    .limit(1)
    .single() as { data: Property | null; error: unknown }

  const currentYear = new Date().getFullYear()

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const [readingsResult, utilityResult, budgetResult] = await Promise.all([
    property
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ? (supabase as any).from('energy_readings').select('*').eq('property_id', property.id).order('reading_date', { ascending: false }).limit(200) as Promise<{ data: EnergyReading[] | null }>
      : Promise.resolve({ data: [] as EnergyReading[] }),
    property
      ? supabase
          .from('financial_records')
          .select('amount, date, title')
          .eq('property_id', property.id)
          .eq('type', 'expense')
          .eq('category', 'utilities')
          .gte('date', `${currentYear}-01-01`)
          .order('date', { ascending: false })
          .limit(50)
      : Promise.resolve({ data: [] }),
    // Utility budget records — sum to get monthly budget target
    property
      ? supabase
          .from('financial_records')
          .select('amount')
          .eq('property_id', property.id)
          .eq('type', 'budget')
          .eq('category', 'utilities')
          .limit(20)
      : Promise.resolve({ data: [] }),
  ])

  const records = ((utilityResult.data ?? []) as Pick<FinancialRecord, 'amount' | 'date' | 'title'>[])
  const ytdUtilities = records.reduce((s, r) => s + r.amount, 0)
  const currentMonth = new Date().getMonth() + 1
  const monthStr = `${currentYear}-${String(currentMonth).padStart(2, '0')}`
  const monthlyUtilities = records
    .filter((r) => r.date.startsWith(monthStr))
    .reduce((s, r) => s + r.amount, 0)
  const utilityBudget = ((budgetResult.data ?? []) as Pick<FinancialRecord, 'amount'>[])
    .reduce((s, r) => s + r.amount, 0)

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader
        title="Energy"
        description={property?.name ?? 'Monitor consumption'}
        action={{ label: 'Log Reading', href: '/energy/new' }}
      />
      <EnergyOverview
        readings={readingsResult.data ?? []}
        ytdUtilities={ytdUtilities}
        monthlyUtilities={monthlyUtilities}
        utilityBudget={utilityBudget}
        currency={property?.currency ?? 'EUR'}
        propertyId={property?.id ?? ''}
      />
    </div>
  )
}
