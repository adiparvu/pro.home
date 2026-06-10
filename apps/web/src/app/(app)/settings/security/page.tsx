import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { SettingsShell } from '@/components/modules/settings/settings-shell'
import { SecuritySettings } from '@/components/modules/settings/security-settings'
import { PageHeader } from '@/components/layout/page-header'

export const metadata: Metadata = {
  title: 'Security — Settings',
}

export default async function SecurityPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader title="Settings" />
      <SettingsShell activeTab="security">
        <SecuritySettings userId={user.id} />
      </SettingsShell>
    </div>
  )
}
