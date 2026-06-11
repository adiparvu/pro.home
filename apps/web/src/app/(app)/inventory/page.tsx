import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import type { InventoryItem } from '@/lib/supabase/types'
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

  const property = await getActiveProperty(supabase, user.id)

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

  const now = new Date()
  const today = now.toISOString().split('T')[0]
  const future30Date = new Date(now)
  future30Date.setDate(future30Date.getDate() + 30)
  const future30 = future30Date.toISOString().split('T')[0]

  const { data: warrantyExpiringItems } = await supabase
    .from('inventory_items')
    .select('*')
    .eq('property_id', property.id)
    .gte('warranty_expires', today)
    .lte('warranty_expires', future30)
    .order('warranty_expires', { ascending: true }) as {
    data: InventoryItem[] | null
    error: unknown
  }

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <InventoryPage property={property} items={items ?? []} warrantyExpiring={warrantyExpiringItems ?? []} />
    </div>
  )
}
