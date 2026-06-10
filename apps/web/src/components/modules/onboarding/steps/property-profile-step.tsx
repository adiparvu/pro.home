'use client'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

interface PropertyProfileStepProps {
  onNext: () => void
  onBack: () => void
}

export function PropertyProfileStep({ onNext, onBack }: PropertyProfileStepProps) {
  return (
    <div className="flex flex-1 flex-col px-4 py-6 max-w-sm mx-auto w-full">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-foreground">Property Details</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Help us understand your property better
        </p>
      </div>

      <div className="flex flex-1 flex-col gap-5">
        <div className="grid grid-cols-2 gap-3">
          <Input
            label="Size (m²)"
            type="number"
            placeholder="e.g., 120"
            hint="Total living area"
          />
          <Input
            label="Year built"
            type="number"
            placeholder="e.g., 1995"
            hint="Optional"
          />
        </div>

        <div className="grid grid-cols-2 gap-3">
          <Input
            label="Bedrooms"
            type="number"
            placeholder="e.g., 3"
          />
          <Input
            label="Bathrooms"
            type="number"
            placeholder="e.g., 2"
          />
        </div>

        <Input
          label="Last renovation"
          type="number"
          placeholder="e.g., 2018"
          hint="Optional"
        />

        <p className="text-xs text-muted-foreground text-center">
          All details can be updated later in Property Settings
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
