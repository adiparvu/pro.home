import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { DepositPage } from '@/components/modules/tenant/deposit-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Deposit Lifecycle' }

export default async function DepositRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Deposit" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sb = supabase as any

  const [{ data: leases }, { data: deductions }] = await Promise.all([
    sb.from('leases').select('id, tenant_name, deposit_amount, deposit_paid, currency, status').eq('property_id', property.id).not('deposit_amount', 'is', null).order('created_at', { ascending: false }),
    sb.from('deposit_deductions').select('*').eq('property_id', property.id).order('created_at', { ascending: false }),
  ])

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <DepositPage
        property={property}
        userId={user.id}
        initialLeases={leases ?? []}
        initialDeductions={deductions ?? []}
      />
    </div>
  )
}
