import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Property, PropertyMember } from '@/lib/supabase/types'
import { PropertyList } from '@/components/modules/property/property-list'
import { PageHeader } from '@/components/layout/page-header'

export const metadata: Metadata = {
  title: 'Properties',
}

export default async function PropertyPage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

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

  const allProperties = (memberships ?? [])
    .map((m) => m.properties)
    .filter((p): p is Property => p !== null)

  const properties = allProperties.filter((p) => p.is_active)
  const archivedProperties = allProperties.filter((p) => !p.is_active)

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader
        title="My Properties"
        description="Manage your properties and their settings"
        action={{ label: 'Add Property', href: '/property/new' }}
      />
      <div className="px-4 py-4 md:px-6 md:py-6">
        <PropertyList properties={properties} archivedProperties={archivedProperties} />
      </div>
    </div>
  )
}
