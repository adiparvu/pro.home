import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { AriaPage } from '@/components/modules/aria/aria-page'
import type { Property, AriaMessage } from '@/lib/supabase/types'

export const metadata: Metadata = { title: 'ARIA — Property Brain' }

export default async function AriaRoute() {
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

  const propertyId = property?.id ?? null

  let messages: AriaMessage[] = []
  if (propertyId) {
    const { data } = await supabase
      .from('aria_messages')
      .select('*')
      .eq('user_id', user.id)
      .eq('property_id', propertyId)
      .order('created_at', { ascending: true })
      .limit(100) as { data: AriaMessage[] | null; error: unknown }
    messages = data ?? []
  }

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <AriaPage userId={user.id} propertyId={propertyId} initialMessages={messages} />
    </div>
  )
}
