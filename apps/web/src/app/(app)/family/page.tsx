import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import type { PropertyMember, PropertyInvitation } from '@/lib/supabase/types'
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

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Family" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sb = supabase as any

  const [membersRes, invitationsRes] = await Promise.all([
    sb
      .from('property_members')
      .select('*')
      .eq('property_id', property.id)
      .eq('status', 'active')
      .order('joined_at', { ascending: true }) as Promise<{ data: PropertyMember[] | null; error: unknown }>,
    sb
      .from('property_invitations')
      .select('*')
      .eq('property_id', property.id)
      .eq('status', 'pending')
      .gt('expires_at', new Date().toISOString())
      .order('created_at', { ascending: false }) as Promise<{ data: PropertyInvitation[] | null; error: unknown }>,
  ])

  const members = membersRes.data ?? []
  const pendingInvitations = invitationsRes.data ?? []
  const myMembership = members.find((m) => m.user_id === user.id) ?? null

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <FamilyPage
        property={property}
        members={members}
        pendingInvitations={pendingInvitations}
        currentUserId={user.id}
        myMembership={myMembership}
      />
    </div>
  )
}
