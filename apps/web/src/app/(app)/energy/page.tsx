import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/layout/page-header'
import { EnergyOverview } from '@/components/modules/energy/energy-overview'

export const metadata: Metadata = { title: 'Energy' }

export default async function EnergyPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <PageHeader title="Energy" description="Monitor consumption and optimize usage" />
      <EnergyOverview />
    </div>
  )
}
