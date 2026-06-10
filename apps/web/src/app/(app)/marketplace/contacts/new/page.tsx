import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { PageHeader } from '@/components/layout/page-header'
import { AddContactForm } from '@/components/modules/marketplace/add-contact-form'

export const metadata: Metadata = { title: 'Add Contact — Marketplace' }

export default async function NewContactPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) redirect('/marketplace')

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader title="Add Contact" description="Save a trusted service provider" backHref="/marketplace" />
      <AddContactForm propertyId={property.id} userId={user.id} />
    </div>
  )
}
