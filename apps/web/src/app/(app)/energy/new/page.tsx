import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { PageHeader } from '@/components/layout/page-header'
import { AddReadingForm } from '@/components/modules/energy/add-reading-form'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Log Reading' }

export default async function NewEnergyReadingPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Log Reading" backHref="/energy" />
        <NoPropertyState />
      </div>
    )
  }

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader title="Log Reading" description={property.name} backHref="/energy" />
      <div className="px-4 py-4 md:px-6 md:py-6 max-w-xl">
        <AddReadingForm propertyId={property.id} userId={user.id} />
      </div>
    </div>
  )
}
