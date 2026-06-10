import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Property, Document } from '@/lib/supabase/types'
import { DocumentsPage } from '@/components/modules/documents/documents-page'

export const metadata: Metadata = { title: 'Documents' }

export default async function DocumentsRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: property } = await supabase
    .from('properties')
    .select('*')
    .eq('owner_id', user.id)
    .order('created_at', { ascending: false })
    .limit(1)
    .single() as { data: Property | null; error: unknown }

  if (!property) redirect('/onboarding/property')

  const { data: documents } = await supabase
    .from('documents')
    .select('*')
    .eq('property_id', property.id)
    .order('created_at', { ascending: false }) as { data: Document[] | null; error: unknown }

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <DocumentsPage
        property={property}
        userId={user.id}
        initialDocuments={documents ?? []}
      />
    </div>
  )
}
