import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { CostSplitPage } from '@/components/modules/finances/cost-split-page'
import type { CostSplit, CostSplitShare } from '@/components/modules/finances/cost-split-page'

export const metadata: Metadata = { title: 'Cost Split' }

export default async function CostSplitRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)
  if (!property) redirect('/onboarding/property')

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: splits } = await (supabase as any)
    .from('cost_splits')
    .select('*')
    .eq('property_id', property.id)
    .order('created_at', { ascending: false }) as { data: CostSplit[] | null }

  const splitIds = (splits ?? []).map((s) => s.id)

  let shares: CostSplitShare[] = []
  if (splitIds.length > 0) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: sharesData } = await (supabase as any)
      .from('cost_split_shares')
      .select('*')
      .in('split_id', splitIds) as { data: CostSplitShare[] | null }
    shares = sharesData ?? []
  }

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <CostSplitPage
        property={property}
        userId={user.id}
        initialSplits={splits ?? []}
        initialShares={shares}
      />
    </div>
  )
}
