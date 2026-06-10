import { type Metadata } from 'next'
import { notFound, redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/layout/page-header'
import { AddPlantForm } from '@/components/modules/garden/add-plant-form'
import type { Property, GardenPlant, GardenZone } from '@/lib/supabase/types'

export const metadata: Metadata = { title: 'Edit Plant' }

export default async function EditPlantPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params
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

  if (!property) redirect('/garden')

  const [plantResult, zonesResult] = await Promise.all([
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('garden_plants').select('*').eq('id', id).eq('property_id', property.id).single() as Promise<{ data: GardenPlant | null }>,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('garden_zones').select('*').eq('property_id', property.id).order('sort_order').limit(50) as Promise<{ data: GardenZone[] | null }>,
  ])

  if (!plantResult.data) notFound()

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader title="Edit Plant" description={plantResult.data.name} backHref="/garden" />
      <AddPlantForm
        propertyId={property.id}
        userId={user.id}
        zones={zonesResult.data ?? []}
        plant={plantResult.data}
      />
    </div>
  )
}
