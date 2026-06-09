import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Property, PropertyMember } from '@/lib/supabase/types'
import { FamilyPage } from '@/components/modules/family/family-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = {
  title: 'Family',
}

export default async function FamilyRoute() {
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  // Get active property memberships
  const { data: myMemberships } = await supabase
    .from('property_members')
    .select('*, properties(*)')
    .eq('user_id', user.id)
    .eq('status', 'active')
    .limit(1) as {
    data: (PropertyMember & { properties: Property | null })[] | null
    error: unknown
  }

  const property = myMemberships?.[0]?.properties ?? null

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
        <PageHeader title="Family" />
        <NoPropertyState />
      </div>
    )
  }

  const { data: members } = await supabase
    .from('property_members')
    .select('*')
    .eq('property_id', property.id)
    .eq('status', 'active')
    .order('joined_at', { ascending: true }) as {
    data: PropertyMember[] | null
    error: unknown
  }

  const myMembership = members?.find((m) => m.user_id === user.id) ?? null

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <FamilyPage
        property={property}
        members={members ?? []}
        currentUserId={user.id}
        myMembership={myMembership}
      />
    </div>
  )
}
