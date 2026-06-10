import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { PageHeader } from '@/components/layout/page-header'
import { SecurityOverview } from '@/components/modules/security/security-overview'
import type { InventoryItem, SecurityState, SecurityEvent, SecuritySchedule } from '@/lib/supabase/types'

export const metadata: Metadata = { title: 'Security' }

const SECURITY_KEYWORDS = ['camera', 'lock', 'alarm', 'sensor', 'doorbell', 'motion', 'detector', 'security']

export default async function SecurityPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Security" description="Protect your home and family" />
        <SecurityOverview propertyId="" securityState={null} events={[]} securityItems={[]} schedules={[]} />
      </div>
    )
  }

  // Parallel fetch: security state, recent events, security inventory items, schedules
  const [stateResult, eventsResult, itemsResult, schedulesResult] = await Promise.all([
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('security_state').select('*').eq('property_id', property.id).maybeSingle() as Promise<{ data: SecurityState | null }>,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('security_events').select('*').eq('property_id', property.id).order('created_at', { ascending: false }).limit(50) as Promise<{ data: SecurityEvent[] | null }>,
    supabase
      .from('inventory_items')
      .select('id, name, brand, category, condition')
      .eq('property_id', property.id)
      .or(SECURITY_KEYWORDS.map((k) => `name.ilike.%${k}%`).join(','))
      .limit(10) as unknown as Promise<{ data: Pick<InventoryItem, 'id' | 'name' | 'brand' | 'category' | 'condition'>[] | null }>,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('security_schedules').select('*').eq('property_id', property.id).order('time_hhmm') as Promise<{ data: SecuritySchedule[] | null }>,
  ])

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader title="Security" description={property.name} />
      <SecurityOverview
        propertyId={property.id}
        securityState={stateResult.data}
        events={eventsResult.data ?? []}
        securityItems={itemsResult.data ?? []}
        schedules={schedulesResult.data ?? []}
      />
    </div>
  )
}
