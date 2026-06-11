import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { TenantPortalPage } from '@/components/modules/tenant/tenant-portal-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Tenant Portal' }

export default async function TenantPortalRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Tenant Portal" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sb = supabase as any

  const [{ data: portals }, { data: requests }] = await Promise.all([
    sb.from('tenant_portals').select('*').eq('property_id', property.id).order('created_at', { ascending: false }),
    sb.from('tenant_requests').select('*').eq('property_id', property.id).order('created_at', { ascending: false }),
  ])

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <TenantPortalPage
        property={property}
        userId={user.id}
        initialPortals={portals ?? []}
        initialRequests={requests ?? []}
      />
    </div>
  )
}
