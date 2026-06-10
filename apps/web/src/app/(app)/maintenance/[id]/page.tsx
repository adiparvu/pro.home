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

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <TaskDetail task={task} />
    </div>
  )
}
