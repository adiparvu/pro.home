import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { BudgetPage } from '@/components/modules/finances/budget-page'
import type { CategoryBudget, SpendingRecord } from '@/components/modules/finances/budget-page'

export const metadata: Metadata = { title: 'Budget' }

export default async function BudgetRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)
  if (!property) redirect('/onboarding/property')

  const now = new Date()
  const year = now.getFullYear()
  const month = String(now.getMonth() + 1).padStart(2, '0')
  const firstDayOfMonth = `${year}-${month}-01`
  const lastDay = new Date(year, now.getMonth() + 1, 0).getDate()
  const lastDayOfMonth = `${year}-${month}-${String(lastDay).padStart(2, '0')}`

  const [{ data: budgets }, { data: spendingRecords }] = await Promise.all([
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any)
      .from('category_budgets')
      .select('*')
      .eq('property_id', property.id)
      .order('category') as Promise<{ data: CategoryBudget[] | null }>,

    supabase
      .from('financial_records')
      .select('category, amount')
      .eq('property_id', property.id)
      .eq('type', 'expense')
      .gte('date', firstDayOfMonth)
      .lte('date', lastDayOfMonth) as unknown as Promise<{ data: SpendingRecord[] | null }>,
  ])

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <BudgetPage
        property={property}
        userId={user.id}
        initialBudgets={budgets ?? []}
        spendingRecords={spendingRecords ?? []}
      />
    </div>
  )
}
