import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { AddPropertyForm } from '@/components/modules/property/add-property-form'
import { PageHeader } from '@/components/layout/page-header'

export const metadata: Metadata = {
  title: 'Add Property',
}

export default async function NewPropertyPage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <PageHeader
        title="Add Property"
        description="Register a new property in your account"
        backHref="/property"
      />
      <div className="px-4 py-4 md:px-6 md:py-6 max-w-2xl">
        <AddPropertyForm userId={user.id} />
      </div>
    </div>
  )
}
