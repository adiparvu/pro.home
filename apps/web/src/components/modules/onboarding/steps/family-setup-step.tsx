'use client'

import { Users } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'

interface FamilySetupStepProps {
  onNext: () => void
  onBack: () => void
}

export function FamilySetupStep({ onNext, onBack }: FamilySetupStepProps) {
  return (
    <div className="flex flex-1 flex-col px-4 py-6 max-w-sm mx-auto w-full">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-foreground">Who lives here?</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Add family members to your household
        </p>
      </div>

      <div className="flex flex-1 flex-col gap-4">
        {/* Current user */}
        <div className="glass-standard rounded-2xl p-4 flex items-center gap-3">
          <Avatar size="md">
            <AvatarFallback>You</AvatarFallback>
          </Avatar>
          <div className="flex-1">
            <p className="text-sm font-semibold text-foreground">You</p>
            <p className="text-xs text-muted-foreground">Account owner</p>
          </div>
          <Badge variant="home" size="sm">Owner</Badge>
        </div>

        {/* Add member prompt */}
        <Button
          variant="secondary"
          size="md"
          fullWidth
          leftIcon={<Users className="h-4 w-4" />}
        >
          Add family member
        </Button>

        <p className="text-xs text-muted-foreground text-center">
          You can invite family members from Settings at any time
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
