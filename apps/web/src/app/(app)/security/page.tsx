import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { PageHeader } from '@/components/layout/page-header'
import { SecurityOverview } from '@/components/modules/security/security-overview'

export const metadata: Metadata = { title: 'Security' }

export default async function SecurityPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <PageHeader title="Security" description="Protect your home and family" />
      <SecurityOverview />
    </div>
  )
}
