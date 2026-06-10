import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Property, PropertyMember } from '@/lib/supabase/types'
import { PageHeader } from '@/components/layout/page-header'
import { AddInventoryItemForm } from '@/components/modules/inventory/add-inventory-item-form'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Add Item' }

export default async function NewInventoryItemPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: myMemberships } = await supabase
    .from('property_members')
    .select('*, properties(*)')
    .eq('user_id', user.id)
    .eq('status', 'active')
    .limit(1) as {
    data: (PropertyMember & { properties: Property | null })[] | null
    error: unknown
  }

  const property = myMemberships?.[0]?.properties ?? null

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
        <PageHeader title="Add Item" backHref="/inventory" />
        <NoPropertyState />
      </div>
    )
  }

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <PageHeader title="Add Item" description={property.name} backHref="/inventory" />
      <div className="px-4 py-4 md:px-6 md:py-6 max-w-xl">
        <AddInventoryItemForm propertyId={property.id} userId={user.id} />
      </div>
    </div>
  )
}
