import { type Metadata } from 'next'
import { redirect, notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Document } from '@/lib/supabase/types'
import { DocumentDetail } from '@/components/modules/documents/document-detail'

export const metadata: Metadata = { title: 'Document' }

interface Props { params: Promise<{ id: string }> }

export default async function DocumentDetailPage({ params }: Props) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: doc } = await supabase
    .from('documents')
    .select('*')
    .eq('id', id)
    .single() as { data: Document | null; error: unknown }

  if (!doc) notFound()

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <DocumentDetail initialDoc={doc} />
    </div>
  )
}
