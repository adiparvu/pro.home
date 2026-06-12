import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { DocumentTemplatesPage } from '@/components/modules/documents/document-templates-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Document Templates' }

export default async function DocumentTemplatesRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Templates" backHref="/documents" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: leases } = await (supabase as any)
    .from('leases')
    .select('id, monthly_rent, currency, status, tenant_name')
    .eq('property_id', property.id)
    .eq('status', 'active')

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: payments } = await (supabase as any)
    .from('rent_payments')
    .select('id, lease_id, amount, currency, month, status')
    .eq('property_id', property.id)
    .order('month', { ascending: false })
    .limit(12)

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <DocumentTemplatesPage
        property={property}
        leases={leases ?? []}
        recentPayments={payments ?? []}
      />
    </div>
  )
}
