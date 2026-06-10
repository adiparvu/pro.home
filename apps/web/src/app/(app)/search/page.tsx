import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { SearchPage } from '@/components/modules/search/search-page'

export const metadata: Metadata = { title: 'Search' }

export default async function SearchRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) redirect('/onboarding/property')

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <SearchPage propertyId={property.id} />
    </div>
  )
}
