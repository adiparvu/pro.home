import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/layout/page-header'
import { AddPlantForm } from '@/components/modules/garden/add-plant-form'
import type { Property, GardenZone } from '@/lib/supabase/types'

export const metadata: Metadata = { title: 'Add Plant — Garden' }

export default async function NewPlantPage() {
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

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: zones } = await (supabase as any).from('garden_zones').select('*').eq('property_id', property.id).order('sort_order', { ascending: true }).limit(50) as { data: GardenZone[] | null }

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader title="Add Plant" description="Track a new plant in your garden" backHref="/garden" />
      <AddPlantForm propertyId={property.id} userId={user.id} zones={zones ?? []} />
    </div>
  )
}
