import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'
import { SeasonalPlannerPage } from '@/components/modules/maintenance/seasonal-planner-page'

export const metadata: Metadata = { title: 'Seasonal Planner' }

export default async function SeasonalPlannerRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Seasonal Planner" backHref="/maintenance" />
        <NoPropertyState />
      </div>
    )
  }

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <SeasonalPlannerPage property={property} userId={user.id} />
    </div>
  )
}
