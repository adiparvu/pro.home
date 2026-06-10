import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { MarketplacePage } from '@/components/modules/marketplace/marketplace-page'
import type { Property, MarketplaceContact, ServiceRequest } from '@/lib/supabase/types'

export const metadata: Metadata = { title: 'Marketplace' }

export default async function MarketplaceRoute() {
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

  const [contactsResult, requestsResult] = await Promise.all([
    propertyId
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ? (supabase as any).from('marketplace_contacts').select('*').eq('property_id', propertyId).order('is_favorite', { ascending: false }).order('name', { ascending: true }).limit(100) as Promise<{ data: MarketplaceContact[] | null }>
      : Promise.resolve({ data: [] as MarketplaceContact[] }),
    propertyId
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ? (supabase as any).from('service_requests').select('*').eq('property_id', propertyId).order('created_at', { ascending: false }).limit(100) as Promise<{ data: ServiceRequest[] | null }>
      : Promise.resolve({ data: [] as ServiceRequest[] }),
  ])

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <MarketplacePage
        propertyId={propertyId}
        initialContacts={contactsResult.data ?? []}
        initialRequests={requestsResult.data ?? []}
        userId={user.id}
      />
    </div>
  )
}
