import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { IntegrationSettings } from '@/components/modules/settings/integration-settings'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Integrations' }

export default async function IntegrationsRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Integrations" backHref="/more" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: webhooks } = await (supabase as any)
    .from('outbound_webhooks')
    .select('*')
    .eq('property_id', property.id)
    .order('created_at', { ascending: false })

  // Get member role to gate owner-only features
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: member } = await ((supabase as any)
    .from('property_members')
    .select('role')
    .eq('property_id', property.id)
    .eq('user_id', user.id)
    .eq('status', 'active')
    .maybeSingle()) as { data: { role: string } | null }

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <IntegrationSettings
        property={property}
        userId={user.id}
        memberRole={member?.role ?? 'guest'}
        initialWebhooks={webhooks ?? []}
      />
    </div>
  )
}
