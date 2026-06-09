import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { SettingsShell } from '@/components/modules/settings/settings-shell'
import { AppearanceSettings } from '@/components/modules/settings/appearance-settings'
import { PageHeader } from '@/components/layout/page-header'

export const metadata: Metadata = {
  title: 'Appearance — Settings',
}

export default async function AppearancePage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <PageHeader title="Settings" />
      <SettingsShell activeTab="appearance">
        <AppearanceSettings />
      </SettingsShell>
    </div>
  )
}
