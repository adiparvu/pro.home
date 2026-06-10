import { type Metadata } from 'next'
import { redirect, notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { InventoryItem } from '@/lib/supabase/types'
import { InventoryItemDetail } from '@/components/modules/inventory/inventory-item-detail'

export const metadata: Metadata = { title: 'Item Detail' }

interface Props { params: Promise<{ id: string }> }

export default async function InventoryItemPage({ params }: Props) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: item } = await supabase
    .from('inventory_items')
    .select('*')
    .eq('id', id)
    .single() as { data: InventoryItem | null; error: unknown }

  if (!item) notFound()

  // Fetch room name if item is assigned to a room
  let roomName: string | null = null
  if (item.room_id) {
    const { data: room } = await supabase
      .from('rooms')
      .select('name')
      .eq('id', item.room_id)
      .single() as { data: { name: string } | null; error: unknown }
    roomName = room?.name ?? null
  }

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <InventoryItemDetail item={item} roomName={roomName} />
    </div>
  )
}
