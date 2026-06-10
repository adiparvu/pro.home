import { type Metadata } from 'next'
import { notFound, redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { PageHeader } from '@/components/layout/page-header'
import { AddGardenTaskForm } from '@/components/modules/garden/add-garden-task-form'
import type { GardenTask, GardenZone, GardenPlant } from '@/lib/supabase/types'

export const metadata: Metadata = { title: 'Edit Task' }

export default async function EditGardenTaskPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) redirect('/garden')

  const [taskResult, zonesResult, plantsResult] = await Promise.all([
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('garden_tasks').select('*').eq('id', id).eq('property_id', property.id).single() as Promise<{ data: GardenTask | null }>,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('garden_zones').select('*').eq('property_id', property.id).order('sort_order').limit(50) as Promise<{ data: GardenZone[] | null }>,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('garden_plants').select('id, name, status').eq('property_id', property.id).order('name').limit(100) as Promise<{ data: Pick<GardenPlant, 'id' | 'name' | 'status'>[] | null }>,
  ])

  if (!taskResult.data) notFound()

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader title="Edit Task" description={taskResult.data.title} backHref="/garden" />
      <AddGardenTaskForm
        propertyId={property.id}
        zones={zonesResult.data ?? []}
        plants={(plantsResult.data ?? []) as GardenPlant[]}
        task={taskResult.data}
      />
    </div>
  )
}
