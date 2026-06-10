import { type Metadata } from 'next'
import { notFound, redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Property, PropertyMember, Room } from '@/lib/supabase/types'
import { PropertyDetail } from '@/components/modules/property/property-detail'

export const metadata: Metadata = {
  title: 'Property',
}

interface Props {
  params: Promise<{ id: string }>
}

export default async function PropertyDetailPage({ params }: Props) {
  const { id } = await params
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: property } = await supabase
    .from('properties')
    .select('*')
    .eq('id', id)
    .single() as { data: Property | null; error: unknown }

  if (!property) notFound()

  // Verify user is a member
  const { data: membership } = await supabase
    .from('property_members')
    .select('*')
    .eq('property_id', id)
    .eq('user_id', user.id)
    .eq('status', 'active')
    .single() as { data: PropertyMember | null; error: unknown }

  if (!membership) notFound()

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sb = supabase as any
  const [membersRes, roomsRes] = await Promise.all([
    sb.from('property_members').select('*').eq('property_id', id).eq('status', 'active') as Promise<{ data: PropertyMember[] | null; error: unknown }>,
    sb.from('rooms').select('*').eq('property_id', id).order('floor').order('sort_order') as Promise<{ data: Room[] | null; error: unknown }>,
  ])

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <PropertyDetail
        property={property}
        membership={membership}
        members={membersRes.data ?? []}
        rooms={roomsRes.data ?? []}
      />
    </div>
  )
}
