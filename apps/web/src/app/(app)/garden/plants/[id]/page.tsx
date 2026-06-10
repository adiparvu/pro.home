import { type Metadata } from 'next'
import { notFound, redirect } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { PageHeader } from '@/components/layout/page-header'
import { PlantDetailView } from '@/components/modules/garden/plant-detail-view'
import type { GardenPlant, GardenZone } from '@/lib/supabase/types'

export const metadata: Metadata = { title: 'Plant Detail' }

export default async function PlantDetailPage({
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

  const [plantResult, zonesResult] = await Promise.all([
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('garden_plants').select('*').eq('id', id).eq('property_id', property.id).single() as Promise<{ data: GardenPlant | null }>,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('garden_zones').select('id, name').eq('property_id', property.id).order('sort_order').limit(50) as Promise<{ data: Pick<GardenZone, 'id' | 'name'>[] | null }>,
  ])

  if (!plantResult.data) notFound()

  const zoneMap = new Map((zonesResult.data ?? []).map((z) => [z.id, z.name]))

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader
        title={plantResult.data.name}
        description={plantResult.data.species ?? plantResult.data.common_name ?? 'Plant'}
        backHref="/garden"
        action={{ label: 'Edit', href: `/garden/plants/${id}/edit` }}
      />
      <PlantDetailView plant={plantResult.data} zoneName={plantResult.data.zone_id ? (zoneMap.get(plantResult.data.zone_id) ?? null) : null} />
    </div>
  )
}
