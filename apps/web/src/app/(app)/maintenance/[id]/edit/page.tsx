import { type Metadata } from 'next'
import { redirect, notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { MaintenanceTask, Room, InventoryItem } from '@/lib/supabase/types'
import { EditTaskForm } from '@/components/modules/maintenance/edit-task-form'
import { ChevronLeft } from 'lucide-react'
import Link from 'next/link'

export const metadata: Metadata = { title: 'Edit Task' }

interface Props { params: Promise<{ id: string }> }

export default async function EditMaintenanceTaskPage({ params }: Props) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: task } = await supabase
    .from('maintenance_tasks')
    .select('*')
    .eq('id', id)
    .single() as { data: MaintenanceTask | null; error: unknown }

  if (!task) notFound()

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const [membersResult, roomsResult, inventoryResult] = await Promise.all([
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('property_members').select('id, display_name, nickname').eq('property_id', task.property_id).eq('status', 'active') as Promise<{ data: { id: string; display_name: string | null; nickname: string | null }[] | null }>,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('rooms').select('id, name, floor').eq('property_id', task.property_id).order('floor').order('sort_order') as Promise<{ data: Pick<Room, 'id' | 'name' | 'floor'>[] | null }>,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('inventory_items').select('id, name').eq('property_id', task.property_id).order('name').limit(200) as Promise<{ data: Pick<InventoryItem, 'id' | 'name'>[] | null }>,
  ])

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <header className="glass-opaque sticky top-0 z-20 border-b border-border/50 px-4 py-4 md:px-6">
        <div className="flex items-center gap-3">
          <Link
            href={`/maintenance/${id}`}
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg glass-light text-muted-foreground hover:text-foreground transition-colors focus-ring"
          >
            <ChevronLeft className="h-4 w-4" />
          </Link>
          <h1 className="text-lg font-bold text-foreground">Edit Task</h1>
        </div>
      </header>
      <div className="px-4 py-4 md:px-6 md:py-6 max-w-xl">
        <EditTaskForm
          task={task}
          members={membersResult.data ?? []}
          rooms={roomsResult.data ?? []}
          inventoryItems={inventoryResult.data ?? []}
        />
      </div>
    </div>
  )
}
