import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { MeterReadingsPage } from '@/components/modules/energy/meter-readings-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Meter Readings' }

export default async function MeterReadingsRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Meter Readings" backHref="/energy" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: readings } = await (supabase as any)
    .from('meter_readings')
    .select('*')
    .eq('property_id', property.id)
    .order('reading_date', { ascending: false })
    .limit(200)

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <MeterReadingsPage
        property={property}
        userId={user.id}
        initialReadings={readings ?? []}
      />
    </div>
  )
}
