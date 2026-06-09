'use client'

import { Bell, MapPin, Camera, Fingerprint } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'

const PERMISSIONS = [
  {
    icon: Bell,
    title: 'Notifications',
    description: 'Stay updated on maintenance, alerts & ARIA insights',
    color: 'text-primary',
  },
  {
    icon: MapPin,
    title: 'Location',
    description: "Automatically detect your property's local weather",
    color: 'text-[hsl(152,62%,52%)]',
  },
  {
    icon: Camera,
    title: 'Camera',
    description: 'Use M-SCAN™ to catalog your appliances',
    color: 'text-[hsl(185,62%,52%)]',
  },
  {
    icon: Fingerprint,
    title: 'Biometric Auth',
    description: 'Sign in with Face ID or fingerprint',
    color: 'text-[hsl(280,68%,67%)]',
  },
]

interface PermissionsStepProps {
  onNext: () => void
  onBack: () => void
}

export function PermissionsStep({ onNext, onBack }: PermissionsStepProps) {
  return (
    <div className="flex flex-1 flex-col px-4 py-6 max-w-sm mx-auto w-full">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-foreground">A few permissions</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          These help PRV HOUSE work better for you
        </p>
      </div>

      <div className="flex flex-1 flex-col gap-3">
        {PERMISSIONS.map((perm) => (
          <Card key={perm.title} variant="default" padding="md">
            <div className="flex items-start gap-3">
              <div className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-xl glass-light">
                <perm.icon className={`h-4 w-4 ${perm.color}`} />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-foreground">{perm.title}</p>
                <p className="text-xs text-muted-foreground mt-0.5">{perm.description}</p>
              </div>
            </div>
          </Card>
        ))}

        <p className="text-xs text-muted-foreground text-center mt-2">
          Permission requests appear when you first use each feature
        </p>

        <div className="flex-1" />

        <div className="flex gap-3">
          <Button type="button" variant="ghost" size="lg" onClick={onBack}>
            Back
          </Button>
          <Button size="lg" fullWidth onClick={onNext}>
            Continue
          </Button>
        </div>
      </div>
    </div>
  )
}
