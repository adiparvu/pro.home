import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { ForecastPage } from '@/components/modules/finances/forecast-page'

export const metadata: Metadata = { title: 'Forecast' }

export default async function ForecastRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)
  if (!property) redirect('/onboarding/property')

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <ForecastPage property={property} />
    </div>
  )
}
