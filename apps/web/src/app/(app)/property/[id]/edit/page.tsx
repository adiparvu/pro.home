import { type Metadata } from 'next'
import { redirect, notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Property } from '@/lib/supabase/types'
import { PageHeader } from '@/components/layout/page-header'
import { EditPropertyForm } from '@/components/modules/property/edit-property-form'

export const metadata: Metadata = { title: 'Edit Property' }

interface Props {
  params: Promise<{ id: string }>
}

export default async function EditPropertyPage({ params }: Props) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: property } = await supabase
    .from('properties')
    .select('*')
    .eq('id', id)
    .single() as { data: Property | null; error: unknown }

  if (!property) notFound()

  // Only owner/partner can edit
  const { data: member } = await supabase
    .from('property_members')
    .select('role')
    .eq('property_id', id)
    .eq('user_id', user.id)
    .eq('status', 'active')
    .single() as { data: { role: string } | null; error: unknown }

  if (!member || !['owner', 'partner'].includes(member.role)) redirect(`/property/${id}`)

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader
        title="Edit Property"
        description={property.name}
        backHref={`/property/${id}`}
      />
      <div className="px-4 py-4 md:px-6 md:py-6 max-w-xl">
        <EditPropertyForm property={property} />
      </div>
    </div>
  )
}
