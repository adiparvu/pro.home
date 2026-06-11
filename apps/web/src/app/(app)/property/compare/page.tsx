import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Property, PropertyMember } from '@/lib/supabase/types'
import { PropertyComparePage } from '@/components/modules/property/property-compare-page'
import { PageHeader } from '@/components/layout/page-header'

export const metadata: Metadata = { title: 'Compare Properties' }

export default async function PropertyCompareRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: memberships } = await supabase
    .from('property_members')
    .select('*, properties(*)')
    .eq('user_id', user.id)
    .eq('status', 'active')
    .order('joined_at', { ascending: false }) as {
    data: (PropertyMember & { properties: Property | null })[] | null
    error: unknown
  }

  const properties = (memberships ?? [])
    .map((m) => m.properties)
    .filter((p): p is Property => p !== null && p.is_active)

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader title="Compare Properties" description="Side-by-side property metrics" />
      <PropertyComparePage properties={properties} />
    </div>
  )
}
