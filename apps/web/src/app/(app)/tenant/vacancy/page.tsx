import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { VacancyPage } from '@/components/modules/tenant/vacancy-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Vacancy Tracker' }

export default async function VacancyRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Vacancies" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sb = supabase as any

  const [{ data: vacancies }] = await Promise.all([
    sb.from('vacancies').select('*').eq('property_id', property.id).order('start_date', { ascending: false }),
  ])

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <VacancyPage
        property={property}
        userId={user.id}
        initialVacancies={vacancies ?? []}
      />
    </div>
  )
}
