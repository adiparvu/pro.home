import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Providers } from '@/components/layout/providers'
import { SidebarNav } from '@/components/layout/sidebar-nav'
import { BottomTabBar } from '@/components/layout/bottom-tab-bar'
import { QuickActionsFab } from '@/components/layout/quick-actions-fab'
import { GestureManager } from '@/components/layout/gesture-manager'
import { RealtimeNotifications } from '@/components/layout/realtime-notifications'
import { LpbeBackground } from '@/components/glass/lpbe-background'
import { PwaInstallPrompt } from '@/components/layout/pwa-install-prompt'
import type { Profile, UserRole } from '@/lib/supabase/types'

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect('/login')
  }

  const [profileRes, unreadRes, memberRes] = await Promise.all([
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
    supabase
      .from('property_members')
      .select('role')
      .eq('user_id', user.id)
      .eq('status', 'active')
      .order('joined_at', { ascending: true })
      .limit(1)
      .maybeSingle() as unknown as Promise<{ data: { role: UserRole } | null }>,
  ])

  if (profileRes.data && !profileRes.data.onboarding_completed) {
    redirect('/onboarding')
  }

  const unreadCount = unreadRes.count ?? 0
  const memberRole = memberRes.data?.role ?? null

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
            className="flex flex-1 flex-col min-h-0 transition-all duration-slow md:ml-[72px] lg:ml-[260px]"
            id="main-content"
          >
            {children}
          </main>
        </div>

        {/* Mobile Bottom Tab Bar */}
        <BottomTabBar unreadCount={unreadCount} />

        {/* Role-aware quick actions */}
        <QuickActionsFab role={memberRole} />

        {/* Mobile gestures: edge-swipe back, pull-to-refresh */}
        <GestureManager />

        {/* Live notification toasts + badge refresh */}
        <RealtimeNotifications userId={user.id} />

        {/* PWA install prompt */}
        <PwaInstallPrompt />
      </div>
    </Providers>
  )
}
