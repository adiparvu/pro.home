import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/layout/page-header'
import { EnergyOverview } from '@/components/modules/energy/energy-overview'
import type { Property, FinancialRecord } from '@/lib/supabase/types'

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

  // Fetch utility expenses from financial records for the current year
  const currentYear = new Date().getFullYear()
  const { data: utilityRecords } = property
    ? await supabase
        .from('financial_records')
        .select('amount, date, title')
        .eq('property_id', property.id)
        .eq('type', 'expense')
        .eq('category', 'utilities')
        .gte('date', `${currentYear}-01-01`)
        .order('date', { ascending: false })
        .limit(50)
    : { data: null }

  const records = (utilityRecords ?? []) as Pick<FinancialRecord, 'amount' | 'date' | 'title'>[]
  const ytdUtilities = records.reduce((s, r) => s + r.amount, 0)

  // Current month utilities
  const currentMonth = new Date().getMonth() + 1
  const monthStr = `${currentYear}-${String(currentMonth).padStart(2, '0')}`
  const monthlyUtilities = records
    .filter((r) => r.date.startsWith(monthStr))
    .reduce((s, r) => s + r.amount, 0)

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <PageHeader title="Energy" description="Monitor consumption and optimize usage" />
      <EnergyOverview
        ytdUtilities={ytdUtilities}
        monthlyUtilities={monthlyUtilities}
        currency={property?.currency ?? 'EUR'}
        hasRealData={records.length > 0}
      />
    </div>
  )
}
