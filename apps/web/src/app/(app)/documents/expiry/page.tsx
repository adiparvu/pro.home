import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { ExpiryRadarPage } from '@/components/modules/documents/expiry-radar-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Expiry Radar' }

export default async function ExpiryRadarRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Expiry Radar" />
        <NoPropertyState />
      </div>
    )
  }

  const [docsResult, inventoryResult, leasesResult] = await Promise.all([
    supabase
      .from('documents')
      .select('id, name, category, expires_at')
      .eq('property_id', property.id)
      .not('expires_at', 'is', null)
      .order('expires_at', { ascending: true }),
    supabase
      .from('inventory_items')
      .select('id, name, category, warranty_expires')
      .eq('property_id', property.id)
      .not('warranty_expires', 'is', null)
      .order('warranty_expires', { ascending: true }),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any)
      .from('leases')
      .select('id, tenant_name, status, end_date')
      .eq('property_id', property.id)
      .not('end_date', 'is', null)
      .order('end_date', { ascending: true }),
  ])

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <ExpiryRadarPage
        property={property}
        documents={docsResult.data ?? []}
        inventoryItems={inventoryResult.data ?? []}
        leases={leasesResult.data ?? []}
      />
    </div>
  )
}
