import { Home, Sparkles, Shield, Zap } from 'lucide-react'
import { Button } from '@/components/ui/button'
import Link from 'next/link'

interface WelcomeStepProps {
  onNext: () => void
}

export function WelcomeStep({ onNext }: WelcomeStepProps) {
  return (
    <div className="flex flex-1 flex-col items-center justify-between px-6 pt-safe pt-16 pb-12">
      {/* Hero Section */}
      <div className="flex flex-1 flex-col items-center justify-center gap-8 text-center max-w-sm">
        <div className="relative">
          <div className="flex h-28 w-28 items-center justify-center rounded-[2rem] bg-primary shadow-glow-home">
            <Home className="h-14 w-14 text-white" />
          </div>
          {/* Orbiting icons */}
          <div className="absolute -right-2 -top-2 flex h-9 w-9 items-center justify-center rounded-xl bg-[hsl(280,68%,47%)]/80 shadow-glow-aria">
            <Sparkles className="h-4 w-4 text-white" />
          </div>
          <div className="absolute -bottom-2 -right-4 flex h-9 w-9 items-center justify-center rounded-xl bg-[hsl(0,68%,44%)]/80">
            <Shield className="h-4 w-4 text-white" />
          </div>
          <div className="absolute -bottom-2 -left-4 flex h-9 w-9 items-center justify-center rounded-xl bg-[hsl(152,62%,38%)]/80 shadow-glow-energy">
            <Zap className="h-4 w-4 text-white" />
          </div>
        </div>

        <div className="flex flex-col gap-3">
          <h1 className="text-4xl font-black tracking-tight text-gradient">
            Welcome to<br />PRV HOUSE
          </h1>
          <p className="text-base text-muted-foreground text-balance leading-relaxed">
            The intelligent property operating system. Monitor, maintain, and master your home.
          </p>
        </div>

        {/* Feature Pills */}
        <div className="flex flex-wrap justify-center gap-2">
          {[
            '🏠 Property Management',
            '🤖 AI Property Brain',
            '🔒 Security',
            '⚡ Energy',
            '🔧 Maintenance',
          ].map((feature) => (
            <span
              key={feature}
              className="glass-light rounded-full px-3 py-1 text-xs font-medium text-muted-foreground"
            >
              {feature}
            </span>
          ))}
        </div>
      </div>

      {/* CTA */}
      <div className="flex w-full max-w-sm flex-col gap-3">
        <Button fullWidth size="xl" onClick={onNext}>
          Get Started
        </Button>
        <Link href="/login" className="text-center">
          <span className="text-sm text-muted-foreground hover:text-foreground transition-colors">
            Already have an account?{' '}
            <span className="text-primary">Sign in</span>
          </span>
        </Link>
      </div>
    </div>
  )
}
