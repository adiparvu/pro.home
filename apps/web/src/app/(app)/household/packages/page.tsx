import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { PackagesPage } from '@/components/modules/household/packages-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Packages' }

export default async function PackagesRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Packages" backHref="/household" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: packages } = await (supabase as any)
    .from('packages')
    .select('*')
    .eq('property_id', property.id)
    .order('created_at', { ascending: false })

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PackagesPage
        property={property}
        userId={user.id}
        initialPackages={packages ?? []}
      />
    </div>
  )
}
