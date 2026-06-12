import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { CompliancePage } from '@/components/modules/documents/compliance-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Compliance Certificates' }

export default async function ComplianceRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Compliance" backHref="/documents" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: certs } = await (supabase as any)
    .from('compliance_certificates')
    .select('*')
    .eq('property_id', property.id)
    .order('expiry_date', { ascending: true, nullsFirst: false })

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <CompliancePage
        property={property}
        userId={user.id}
        initialCerts={certs ?? []}
      />
    </div>
  )
}
