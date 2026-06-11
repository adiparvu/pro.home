import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { MortgagePage } from '@/components/modules/finances/mortgage-page'
import type { Mortgage } from '@/components/modules/finances/mortgage-page'

export const metadata: Metadata = { title: 'Mortgage' }

export default async function MortgageRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)
  if (!property) redirect('/onboarding/property')

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: mortgages } = await (supabase as any)
    .from('mortgages')
    .select('*')
    .eq('property_id', property.id)
    .order('created_at', { ascending: false }) as { data: Mortgage[] | null }

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <MortgagePage
        property={property}
        userId={user.id}
        initialMortgages={mortgages ?? []}
      />
    </div>
  )
}
