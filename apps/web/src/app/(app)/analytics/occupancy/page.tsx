import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { OccupancyPage } from '@/components/modules/analytics/occupancy-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Occupancy Dashboard' }

export default async function OccupancyRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Occupancy" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: vacancies } = await (supabase as any)
    .from('vacancies')
    .select('id, start_date, end_date, expected_rent_loss, currency')
    .eq('property_id', property.id)
    .order('start_date', { ascending: true })

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: leases } = await (supabase as any)
    .from('leases')
    .select('id, monthly_rent, currency, status')
    .eq('property_id', property.id)

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <OccupancyPage
        property={property}
        initialVacancies={vacancies ?? []}
        initialLeases={leases ?? []}
      />
    </div>
  )
}
