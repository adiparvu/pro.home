import { type Metadata } from 'next'
import { notFound, redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Property, PropertyMember } from '@/lib/supabase/types'
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

  const { data: members } = await supabase
    .from('property_members')
    .select('*')
    .eq('property_id', id)
    .eq('status', 'active') as { data: PropertyMember[] | null; error: unknown }

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <PropertyDetail
        property={property}
        membership={membership}
        members={members ?? []}
      />
    </div>
  )
}
