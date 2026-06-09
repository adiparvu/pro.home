'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { AnimatePresence, motion } from 'framer-motion'
import { WelcomeStep } from './steps/welcome-step'
import { AddPropertyStep } from './steps/add-property-step'
import { PropertyProfileStep } from './steps/property-profile-step'
import { FamilySetupStep } from './steps/family-setup-step'
import { PermissionsStep } from './steps/permissions-step'
import { AriaIntroStep } from './steps/aria-intro-step'
import { createClient } from '@/lib/supabase/client'
import type { Profile } from '@/lib/supabase/types'

const TOTAL_STEPS = 6

interface OnboardingFlowProps {
  userId: string
  currentStep?: number
}

export function OnboardingFlow({ userId, currentStep = 0 }: OnboardingFlowProps) {
  const router = useRouter()
  const [step, setStep] = React.useState(currentStep)
  const [direction, setDirection] = React.useState(1)
  const [isLoading, setIsLoading] = React.useState(false)

  async function persistStep(newStep: number) {
    const supabase = createClient()
    // Supabase generic inference doesn't resolve update() type with manual types — cast via any
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('profiles').update({ onboarding_step: newStep } satisfies Partial<Profile>).eq('id', userId)
  }

  async function goNext() {
    if (step < TOTAL_STEPS - 1) {
      const nextStep = step + 1
      setDirection(1)
      setStep(nextStep)
      await persistStep(nextStep)
    } else {
      await completeOnboarding()
    }
  }

  async function goPrev() {
    if (step > 0) {
      const prevStep = step - 1
      setDirection(-1)
      setStep(prevStep)
      await persistStep(prevStep)
    }
  }

  async function completeOnboarding() {
    setIsLoading(true)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('profiles').update({ onboarding_completed: true, onboarding_step: TOTAL_STEPS } satisfies Partial<Profile>).eq('id', userId)

    router.push('/')
    router.refresh()
  }

  const steps = [
    <WelcomeStep key="welcome" onNext={goNext} />,
    <AddPropertyStep key="property" userId={userId} onNext={goNext} onBack={goPrev} />,
    <PropertyProfileStep key="profile" onNext={goNext} onBack={goPrev} />,
    <FamilySetupStep key="family" onNext={goNext} onBack={goPrev} />,
    <PermissionsStep key="permissions" onNext={goNext} onBack={goPrev} />,
    <AriaIntroStep key="aria" onNext={completeOnboarding} onBack={goPrev} />,
  ]

  return (
    <div className="relative min-h-dvh flex flex-col">
      {/* Progress Header (steps 1–5, not welcome) */}
      {step > 0 && step < TOTAL_STEPS - 1 && (
        <header className="pt-safe px-4 pt-4 pb-2">
          <div className="flex items-center justify-between max-w-sm mx-auto">
            <span className="text-xs text-muted-foreground">
              Step {step} of {TOTAL_STEPS - 2}
            </span>
            <div className="flex gap-1.5">
              {Array.from({ length: TOTAL_STEPS - 2 }).map((_, i) => (
                <div
                  key={i}
                  className={`h-1.5 rounded-full transition-all duration-normal ${
                    i < step
                      ? 'w-4 bg-primary'
                      : i === step - 1
                        ? 'w-4 bg-primary'
                        : 'w-1.5 bg-muted'
                  }`}
                />
              ))}
            </div>
          </div>
        </header>
      )}

      {/* Step Content */}
      <AnimatePresence mode="wait" initial={false}>
        <motion.div
          key={step}
          initial={{ opacity: 0, x: direction * 32 }}
          animate={{ opacity: 1, x: 0 }}
          exit={{ opacity: 0, x: direction * -32 }}
          transition={{ type: 'spring', stiffness: 380, damping: 30, mass: 0.8 }}
          className="flex flex-1 flex-col"
        >
          {steps[step]}
        </motion.div>
      </AnimatePresence>
    </div>
  )
}
