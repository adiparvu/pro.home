import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { SettingsShell } from '@/components/modules/settings/settings-shell'
import { LanguageSettings } from '@/components/modules/settings/language-settings'
import { PageHeader } from '@/components/layout/page-header'

export const metadata: Metadata = {
  title: 'Language — Settings',
}

export default async function LanguagePage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader title="Settings" />
      <SettingsShell activeTab="language">
        <LanguageSettings />
      </SettingsShell>
    </div>
  )
}
