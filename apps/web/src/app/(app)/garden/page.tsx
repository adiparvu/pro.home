import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/layout/page-header'
import { GardenOverview } from '@/components/modules/garden/garden-overview'
import type { Property, GardenPlant, GardenTask, GardenZone } from '@/lib/supabase/types'

export const metadata: Metadata = { title: 'Garden' }

export default async function GardenPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: property } = await supabase
    .from('properties')
    .select('id, property_members!inner(status)')
    .eq('property_members.user_id', user.id)
    .eq('property_members.status', 'active')
    .eq('is_active', true)
    .order('created_at', { ascending: false })
    .limit(1)
    .single() as { data: Pick<Property, 'id'> | null; error: unknown }

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Garden" description="Plants, tasks & zones" action={{ label: 'Add Plant', href: '/garden/plants/new' }} />
        <GardenOverview propertyId="" plants={[]} tasks={[]} zones={[]} />
      </div>
    )
  }

  const [plantsResult, tasksResult, zonesResult] = await Promise.all([
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('garden_plants').select('*').eq('property_id', property.id).order('name', { ascending: true }).limit(100) as Promise<{ data: GardenPlant[] | null }>,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('garden_tasks').select('*').eq('property_id', property.id).neq('status', 'skipped').order('due_date', { ascending: true }).limit(100) as Promise<{ data: GardenTask[] | null }>,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('garden_zones').select('*').eq('property_id', property.id).order('sort_order', { ascending: true }).limit(50) as Promise<{ data: GardenZone[] | null }>,
  ])

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader title="Garden" description={property ? 'Plants, tasks & zones' : 'Start your garden'} action={{ label: 'Add Plant', href: '/garden/plants/new' }} />
      <GardenOverview
        propertyId={property.id}
        plants={plantsResult.data ?? []}
        tasks={tasksResult.data ?? []}
        zones={zonesResult.data ?? []}
      />
    </div>
  )
}
