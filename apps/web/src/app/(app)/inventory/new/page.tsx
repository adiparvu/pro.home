import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import type { Room } from '@/lib/supabase/types'
import { PageHeader } from '@/components/layout/page-header'
import { AddInventoryItemForm } from '@/components/modules/inventory/add-inventory-item-form'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Add Item' }

export default async function NewInventoryItemPage({
  searchParams,
}: {
  searchParams: Promise<{ barcode?: string }>
}) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { barcode } = await searchParams

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Add Item" backHref="/inventory" />
        <NoPropertyState />
      </div>
    )
  }

  const { data: rooms } = await supabase
    .from('rooms')
    .select('id, name, floor')
    .eq('property_id', property.id)
    .order('floor')
    .order('sort_order') as { data: Pick<Room, 'id' | 'name' | 'floor'>[] | null; error: unknown }

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader title="Add Item" description={property.name} backHref="/inventory" />
      <div className="px-4 py-4 md:px-6 md:py-6 max-w-xl">
        <AddInventoryItemForm
          propertyId={property.id}
          userId={user.id}
          rooms={rooms ?? []}
          initialBarcode={barcode}
        />
      </div>
    </div>
  )
}
