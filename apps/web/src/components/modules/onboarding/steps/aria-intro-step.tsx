'use client'

import { Sparkles } from 'lucide-react'
import { Button } from '@/components/ui/button'

interface AriaIntroStepProps {
  onNext: () => void
  onBack: () => void
}

export function AriaIntroStep({ onNext, onBack }: AriaIntroStepProps) {
  return (
    <div className="flex flex-1 flex-col items-center justify-between px-6 pt-12 pb-12">
      {/* Hero Section */}
      <div className="flex flex-1 flex-col items-center justify-center gap-8 text-center max-w-sm">
        {/* ARIA Orb */}
        <div className="relative">
          <div className="flex h-32 w-32 items-center justify-center rounded-full bg-gradient-to-br from-[hsl(280,68%,57%)] to-[hsl(252,72%,47%)] shadow-glow-aria">
            <Sparkles className="h-16 w-16 text-white" />
          </div>
          {/* Pulse rings */}
          <div className="absolute inset-0 rounded-full bg-[hsl(280,68%,47%)]/20 animate-pulse-soft" />
        </div>

        <div className="flex flex-col gap-3">
          <h2 className="text-3xl font-black tracking-tight">
            Meet{' '}
            <span className="text-gradient-primary">ARIA</span>
          </h2>
          <p className="text-sm text-muted-foreground leading-relaxed">
            Your property&apos;s AI brain. ARIA learns how your home works,
            alerts you to things that matter, and handles the complexity so
            you don&apos;t have to.
          </p>
        </div>

        {/* Capabilities */}
        <div className="flex flex-col gap-2 text-left w-full glass-standard rounded-2xl p-4">
          {[
            '🔮 Predicts issues before they happen',
            '📊 Monitors energy, security & health',
            '🛒 Orders supplies at the right time',
            '💬 Answers any property question',
          ].map((item) => (
            <p key={item} className="text-sm text-muted-foreground">
              {item}
            </p>
          ))}
        </div>
      </div>

      {/* CTA */}
      <div className="flex w-full max-w-sm flex-col gap-3">
        <Button
          size="xl"
          fullWidth
          className="bg-gradient-to-r from-[hsl(280,68%,47%)] to-[hsl(252,72%,47%)]"
          onClick={onNext}
        >
          Enter PRV HOUSE
        </Button>
        <button
          onClick={onBack}
          className="text-sm text-muted-foreground hover:text-foreground transition-colors focus-ring rounded"
        >
          Back
        </button>
      </div>
    </div>
  )
}
