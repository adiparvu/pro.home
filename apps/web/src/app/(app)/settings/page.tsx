import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Profile } from '@/lib/supabase/types'
import { SettingsShell } from '@/components/modules/settings/settings-shell'
import { ProfileSettings } from '@/components/modules/settings/profile-settings'
import { PageHeader } from '@/components/layout/page-header'

export const metadata: Metadata = {
  title: 'Settings',
}

export default async function SettingsPage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', user.id)
    .single() as { data: Profile | null; error: unknown }

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader title="Settings" backHref="/more" />
      <SettingsShell activeTab="profile">
        <ProfileSettings profile={profile} userId={user.id} />
      </SettingsShell>
    </div>
  )
}
