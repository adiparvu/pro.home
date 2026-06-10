import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/layout/page-header'
import { DigitalTwinPage } from '@/components/modules/digital-twin/digital-twin-page'
import type { Property, Room, InventoryItem, MaintenanceTask } from '@/lib/supabase/types'

export const metadata: Metadata = { title: 'Digital Twin' }

export default async function DigitalTwinRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: property } = await supabase
    .from('properties')
    .select('id, name, property_members!inner(status)')
    .eq('property_members.user_id', user.id)
    .eq('property_members.status', 'active')
    .eq('is_active', true)
    .order('created_at', { ascending: false })
    .limit(1)
    .single() as { data: Pick<Property, 'id' | 'name'> | null; error: unknown }

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Digital Twin" description="Interactive floor plan" />
        <DigitalTwinPage propertyId="" rooms={[]} items={[]} tasks={[]} />
      </div>
    )
  }

  const [roomsResult, itemsResult, tasksResult] = await Promise.all([
    supabase
      .from('rooms')
      .select('*')
      .eq('property_id', property.id)
      .order('floor', { ascending: true })
      .order('sort_order', { ascending: true }) as unknown as Promise<{ data: Room[] | null }>,
    supabase
      .from('inventory_items')
      .select('id, name, room_id, condition')
      .eq('property_id', property.id)
      .limit(200) as unknown as Promise<{ data: Pick<InventoryItem, 'id' | 'name' | 'room_id' | 'condition'>[] | null }>,
    supabase
      .from('maintenance_tasks')
      .select('id, title, room_id, status, priority')
      .eq('property_id', property.id)
      .neq('status', 'cancelled')
      .limit(200) as unknown as Promise<{ data: Pick<MaintenanceTask, 'id' | 'title' | 'room_id' | 'status' | 'priority'>[] | null }>,
  ])

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader title="Digital Twin" description={property.name} />
      <DigitalTwinPage
        propertyId={property.id}
        rooms={roomsResult.data ?? []}
        items={(itemsResult.data ?? []) as { id: string; name: string; room_id: string | null; condition: string | null }[]}
        tasks={(tasksResult.data ?? []) as { id: string; title: string; room_id: string | null; status: string; priority: string }[]}
      />
    </div>
  )
}
