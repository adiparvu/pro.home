import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { AriaPage } from '@/components/modules/aria/aria-page'
import type { AriaMessage, InventoryItem, MaintenanceTask } from '@/lib/supabase/types'

export const metadata: Metadata = { title: 'ARIA — Property Brain' }

export interface AriaContextHints {
  overdueTaskCount: number
  hasExpiringWarranties: boolean
  hasEnergyData: boolean
  pendingTaskCount: number
  currentMonth: number
}

export default async function AriaRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  const propertyId = property?.id ?? null

  // Parallel fetch: messages + context hints
  const [messagesResult, tasksResult, inventoryResult, energyResult] = await Promise.all([
    propertyId
      ? supabase.from('aria_messages').select('*').eq('user_id', user.id).eq('property_id', propertyId).order('created_at', { ascending: true }).limit(100) as unknown as Promise<{ data: AriaMessage[] | null }>
      : Promise.resolve({ data: [] as AriaMessage[] }),
    propertyId
      ? supabase.from('maintenance_tasks').select('status, due_date').eq('property_id', propertyId).neq('status', 'cancelled').neq('status', 'completed') as unknown as Promise<{ data: Pick<MaintenanceTask, 'status' | 'due_date'>[] | null }>
      : Promise.resolve({ data: [] }),
    propertyId
      ? supabase.from('inventory_items').select('warranty_expires').eq('property_id', propertyId).not('warranty_expires', 'is', null).limit(50) as unknown as Promise<{ data: Pick<InventoryItem, 'warranty_expires'>[] | null }>
      : Promise.resolve({ data: [] }),
    propertyId
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ? (supabase as any).from('energy_readings').select('id').eq('property_id', propertyId).limit(1) as Promise<{ data: { id: string }[] | null }>
      : Promise.resolve({ data: [] }),
  ])

  const tasks = (tasksResult.data ?? []) as Pick<MaintenanceTask, 'status' | 'due_date'>[]
  const inventory = (inventoryResult.data ?? []) as Pick<InventoryItem, 'warranty_expires'>[]

  const now = new Date()
  const in90Days = new Date(now.getTime() + 90 * 24 * 60 * 60 * 1000)

  const contextHints: AriaContextHints = {
    overdueTaskCount: tasks.filter((t) => t.status === 'overdue').length,
    pendingTaskCount: tasks.filter((t) => t.status === 'pending').length,
    hasExpiringWarranties: inventory.some((i) => {
      if (!i.warranty_expires) return false
      const exp = new Date(i.warranty_expires)
      return exp > now && exp < in90Days
    }),
    hasEnergyData: (energyResult.data ?? []).length > 0,
    currentMonth: now.getMonth() + 1,
  }

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <AriaPage
        userId={user.id}
        propertyId={propertyId}
        initialMessages={messagesResult.data ?? []}
        contextHints={contextHints}
      />
    </div>
  )
}
