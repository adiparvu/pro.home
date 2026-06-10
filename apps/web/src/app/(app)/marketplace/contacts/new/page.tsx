import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/layout/page-header'
import { AddContactForm } from '@/components/modules/marketplace/add-contact-form'
import type { Property } from '@/lib/supabase/types'

export const metadata: Metadata = { title: 'Add Contact — Marketplace' }

export default async function NewContactPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: property } = await supabase
    .from('properties')
    .select('id, property_members!inner(status)')
    .eq('property_members.user_id', user.id)
    .eq('property_members.status', 'active')
    .eq('is_active', true)
    .order('created_at', { ascending: false })
    .limit(1)
    .single() as { data: Pick<Property, 'id'> | null; error: unknown }

  if (!property) redirect('/marketplace')

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <PageHeader title="Add Contact" description="Save a trusted service provider" backHref="/marketplace" />
      <AddContactForm propertyId={property.id} userId={user.id} />
    </div>
  )
}
