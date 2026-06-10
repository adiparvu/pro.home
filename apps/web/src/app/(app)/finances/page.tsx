import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Property, FinancialRecord } from '@/lib/supabase/types'
import { FinancesPage } from '@/components/modules/finances/finances-page'

export const metadata: Metadata = { title: 'Finances' }

export default async function FinancesRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: property } = await supabase
    .from('properties')
    .select('*')
    .eq('owner_id', user.id)
    .order('created_at', { ascending: false })
    .limit(1)
    .single() as { data: Property | null; error: unknown }

  if (!property) redirect('/onboarding/property')

  const { data: records } = await supabase
    .from('financial_records')
    .select('*')
    .eq('property_id', property.id)
    .order('date', { ascending: false }) as { data: FinancialRecord[] | null; error: unknown }

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <FinancesPage
        property={property}
        userId={user.id}
        initialRecords={records ?? []}
      />
    </div>
  )
}
