import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Profile } from '@/lib/supabase/types'
import { OnboardingFlow } from '@/components/modules/onboarding/onboarding-flow'
import { Providers } from '@/components/layout/providers'
import { LpbeBackground } from '@/components/glass/lpbe-background'

export const metadata: Metadata = {
  title: 'Set Up Your Home',
}

export default async function OnboardingPage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect('/login')
  }

  // If onboarding already completed, go to dashboard
  const { data: profile } = await supabase
    .from('profiles')
    .select('onboarding_completed, onboarding_step')
    .eq('id', user.id)
    .single() as { data: Pick<Profile, 'onboarding_completed' | 'onboarding_step'> | null; error: unknown }

  if (profile?.onboarding_completed) {
    redirect('/')
  }

  return (
    <Providers>
      <div className="relative min-h-dvh overflow-hidden">
        <LpbeBackground />
        <div className="absolute inset-0 bg-black/30" aria-hidden="true" />
        <div className="relative z-10">
          <OnboardingFlow
            userId={user.id}
            currentStep={profile?.onboarding_step ?? 0}
          />
        </div>
      </div>
    </Providers>
  )
}
