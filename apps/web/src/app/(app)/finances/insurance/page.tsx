import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { InsurancePage } from '@/components/modules/finances/insurance-page'
import type { InsurancePolicy } from '@/components/modules/finances/insurance-page'

export const metadata: Metadata = { title: 'Insurance' }

export default async function InsuranceRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)
  if (!property) redirect('/onboarding/property')

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: policies } = await (supabase as any)
    .from('insurance_policies')
    .select('*')
    .eq('property_id', property.id)
    .order('end_date', { ascending: true, nullsFirst: false }) as { data: InsurancePolicy[] | null }

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <InsurancePage
        property={property}
        userId={user.id}
        initialPolicies={policies ?? []}
      />
    </div>
  )
}
