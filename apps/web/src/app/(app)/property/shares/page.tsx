import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { SharesPage } from '@/components/modules/property/shares-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Share Register' }

export default async function SharesRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Share Register" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: shares } = await (supabase as any)
    .from('property_shares')
    .select('*')
    .eq('property_id', property.id)
    .order('share_percentage', { ascending: false })

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <SharesPage
        property={property}
        userId={user.id}
        initialShares={shares ?? []}
      />
    </div>
  )
}
