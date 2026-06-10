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

  // Check if onboarding is complete
  const { data: profile } = await supabase
    .from('profiles')
    .select('onboarding_completed')
    .eq('id', user.id)
    .single() as { data: Pick<Profile, 'onboarding_completed'> | null; error: unknown }

  if (profile && !profile.onboarding_completed) {
    redirect('/onboarding')
  }

  return (
    <Providers>
      <div className="relative min-h-dvh">
        {/* Living Property Background */}
        <LpbeBackground />

        {/* App Shell */}
        <div className="relative z-10 flex min-h-dvh">
          {/* Sidebar (tablet/desktop) */}
          <SidebarNav />

          {/* Main Content */}
          <main
            className="flex flex-1 flex-col transition-all duration-slow md:ml-[72px] lg:ml-[260px]"
            id="main-content"
          >
            {children}
          </main>
        </div>

        {/* Mobile Bottom Tab Bar */}
        <BottomTabBar />
      </div>
    </Providers>
  )
}
