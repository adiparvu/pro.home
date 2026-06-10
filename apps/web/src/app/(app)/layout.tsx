import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Providers } from '@/components/layout/providers'
import { SidebarNav } from '@/components/layout/sidebar-nav'
import { BottomTabBar } from '@/components/layout/bottom-tab-bar'
import { LpbeBackground } from '@/components/glass/lpbe-background'
import type { Profile } from '@/lib/supabase/types'

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect('/login')
  }

  const [profileRes, unreadRes] = await Promise.all([
    supabase
      .from('profiles')
      .select('onboarding_completed')
      .eq('id', user.id)
      .single() as unknown as Promise<{ data: Pick<Profile, 'onboarding_completed'> | null }>,
    supabase
      .from('notifications')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .eq('status', 'unread'),
  ])

  if (profileRes.data && !profileRes.data.onboarding_completed) {
    redirect('/onboarding')
  }

  const unreadCount = unreadRes.count ?? 0

  return (
    <Providers>
      <div className="relative min-h-dvh">
        {/* Living Property Background */}
        <LpbeBackground />

        {/* App Shell */}
        <div className="relative z-10 flex min-h-dvh">
          {/* Sidebar (tablet/desktop) */}
          <SidebarNav unreadCount={unreadCount} />

          {/* Main Content */}
          <main
            className="flex flex-1 flex-col transition-all duration-slow md:ml-[72px] lg:ml-[260px]"
            id="main-content"
          >
            {children}
          </main>
        </div>

        {/* Mobile Bottom Tab Bar */}
        <BottomTabBar unreadCount={unreadCount} />
      </div>
    </Providers>
  )
}
