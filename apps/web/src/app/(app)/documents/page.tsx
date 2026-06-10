import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Property, Document } from '@/lib/supabase/types'
import { DocumentsPage } from '@/components/modules/documents/documents-page'

export const metadata: Metadata = { title: 'Documents' }

export default async function DocumentsRoute({
  searchParams,
}: {
  searchParams: Promise<{ upload?: string }>
}) {
  const { upload } = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: property } = await supabase
    .from('properties')
    .select('*, property_members!inner(role, status)')
    .eq('property_members.user_id', user.id)
    .eq('property_members.status', 'active')
    .eq('is_active', true)
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
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <DocumentsPage
        property={property}
        userId={user.id}
        initialDocuments={documents ?? []}
        initialShowUpload={upload === '1'}
      />
    </div>
  )
}
