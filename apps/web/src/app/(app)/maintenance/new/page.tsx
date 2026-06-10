import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Property, PropertyMember, Room, InventoryItem } from '@/lib/supabase/types'
import { PageHeader } from '@/components/layout/page-header'
import { AddTaskForm } from '@/components/modules/maintenance/add-task-form'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'New Task' }

export default async function NewMaintenanceTaskPage() {
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
      <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
        <PageHeader title="New Task" backHref="/maintenance" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const [membersResult, roomsResult, inventoryResult] = await Promise.all([
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('property_members').select('id, display_name, nickname').eq('property_id', property.id).eq('status', 'active') as Promise<{ data: { id: string; display_name: string | null; nickname: string | null }[] | null }>,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('rooms').select('id, name, floor').eq('property_id', property.id).order('floor').order('sort_order') as Promise<{ data: Pick<Room, 'id' | 'name' | 'floor'>[] | null }>,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('inventory_items').select('id, name').eq('property_id', property.id).order('name').limit(200) as Promise<{ data: Pick<InventoryItem, 'id' | 'name'>[] | null }>,
  ])

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <PageHeader title="New Task" description={property.name} backHref="/maintenance" />
      <div className="px-4 py-4 md:px-6 md:py-6 max-w-xl">
        <AddTaskForm
          propertyId={property.id}
          userId={user.id}
          members={membersResult.data ?? []}
          rooms={roomsResult.data ?? []}
          inventoryItems={inventoryResult.data ?? []}
        />
      </div>
    </div>
  )
}
