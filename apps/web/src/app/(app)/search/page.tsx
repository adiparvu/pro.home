import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Property } from '@/lib/supabase/types'
import { SearchPage } from '@/components/modules/search/search-page'

export const metadata: Metadata = { title: 'Search' }

export default async function SearchRoute() {
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

  if (!property) redirect('/onboarding/property')

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <SearchPage propertyId={property.id} />
    </div>
  )
}
