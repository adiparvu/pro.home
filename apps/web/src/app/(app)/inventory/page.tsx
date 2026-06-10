import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Property, PropertyMember, InventoryItem } from '@/lib/supabase/types'
import { InventoryPage } from '@/components/modules/inventory/inventory-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = {
  title: 'Inventory',
}

export default async function InventoryRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: myMemberships } = await supabase
    .from('property_members')
    .select('*, properties(*)')
    .eq('user_id', user.id)
    .eq('status', 'active')
    .limit(1) as {
    data: (PropertyMember & { properties: Property | null })[] | null
    error: unknown
  }

  const property = myMemberships?.[0]?.properties ?? null

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Inventory" />
        <NoPropertyState />
      </div>
    )
  }

  const { data: items } = await supabase
    .from('inventory_items')
    .select('*')
    .eq('property_id', property.id)
    .order('created_at', { ascending: false }) as {
    data: InventoryItem[] | null
    error: unknown
  }

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <InventoryPage property={property} items={items ?? []} />
    </div>
  )
}
