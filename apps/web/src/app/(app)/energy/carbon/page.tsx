import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { CarbonPage } from '@/components/modules/energy/carbon-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Carbon Footprint' }

export default async function CarbonRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Carbon Footprint" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: readings } = await (supabase as any)
    .from('meter_readings')
    .select('id, meter_type, value, unit, reading_date, created_at')
    .eq('property_id', property.id)
    .order('reading_date', { ascending: false })
    .limit(500)

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let { data: carbonSettings } = await (supabase as any)
    .from('carbon_settings')
    .select('*')
    .eq('property_id', property.id)
    .single()

  if (!carbonSettings) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: inserted } = await (supabase as any)
      .from('carbon_settings')
      .upsert({
        property_id: property.id,
        electricity_factor: 0.233,
        gas_factor: 2.04,
        water_factor: 0.001,
        area_sqm: null,
        occupants: 1,
      }, { onConflict: 'property_id' })
      .select()
      .single()
    carbonSettings = inserted ?? {
      electricity_factor: 0.233,
      gas_factor: 2.04,
      water_factor: 0.001,
      area_sqm: null,
      occupants: 1,
    }
  }

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <CarbonPage
        property={property}
        initialReadings={readings ?? []}
        initialSettings={carbonSettings}
      />
    </div>
  )
}
