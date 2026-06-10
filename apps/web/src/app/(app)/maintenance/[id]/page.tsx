import { type Metadata } from 'next'
import { redirect, notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { MaintenanceTask } from '@/lib/supabase/types'
import { TaskDetail } from '@/components/modules/maintenance/task-detail'

export const metadata: Metadata = { title: 'Task Detail' }

interface Props { params: Promise<{ id: string }> }

export default async function MaintenanceTaskPage({ params }: Props) {
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

  // Fetch related names in parallel
  const [assigneeResult, roomResult, inventoryResult] = await Promise.all([
    task.assigned_to_member_id
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ? (supabase as any).from('property_members').select('display_name, nickname').eq('id', task.assigned_to_member_id).single() as Promise<{ data: { display_name: string | null; nickname: string | null } | null }>
      : Promise.resolve({ data: null }),
    task.room_id
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ? (supabase as any).from('rooms').select('name').eq('id', task.room_id).single() as Promise<{ data: { name: string } | null }>
      : Promise.resolve({ data: null }),
    task.inventory_item_id
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ? (supabase as any).from('inventory_items').select('name').eq('id', task.inventory_item_id).single() as Promise<{ data: { name: string } | null }>
      : Promise.resolve({ data: null }),
  ])

  const assignee = assigneeResult.data
  const assigneeName = assignee
    ? (assignee.nickname ?? assignee.display_name ?? null)
    : null

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <TaskDetail
        task={task}
        assigneeName={assigneeName}
        roomName={roomResult.data?.name ?? null}
        inventoryItemName={inventoryResult.data?.name ?? null}
      />
    </div>
  )
}
