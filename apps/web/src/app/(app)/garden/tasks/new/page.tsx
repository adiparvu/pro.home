import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/layout/page-header'
import { AddGardenTaskForm } from '@/components/modules/garden/add-garden-task-form'
import type { Property, GardenZone, GardenPlant } from '@/lib/supabase/types'

export const metadata: Metadata = { title: 'Add Garden Task' }

export default async function NewGardenTaskPage() {
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

  if (!property) redirect('/garden')

  const [zonesResult, plantsResult] = await Promise.all([
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('garden_zones').select('*').eq('property_id', property.id).order('sort_order', { ascending: true }).limit(50) as Promise<{ data: GardenZone[] | null }>,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('garden_plants').select('id, name, status').eq('property_id', property.id).order('name', { ascending: true }).limit(100) as Promise<{ data: Pick<GardenPlant, 'id' | 'name' | 'status'>[] | null }>,
  ])

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <PageHeader title="Add Garden Task" description="Schedule a garden activity" backHref="/garden" />
      <AddGardenTaskForm
        propertyId={property.id}
        zones={zonesResult.data ?? []}
        plants={(plantsResult.data ?? []) as GardenPlant[]}
      />
    </div>
  )
}
