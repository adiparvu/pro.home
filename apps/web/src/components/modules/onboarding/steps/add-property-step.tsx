'use client'

import * as React from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Building2, House, Hotel, Home } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card } from '@/components/ui/card'
import { createClient } from '@/lib/supabase/client'
import { cn } from '@/lib/utils'
import type { PropertyType, Property } from '@/lib/supabase/types'

const propertySchema = z.object({
  name: z.string().min(1, 'Property name is required').max(100),
  address_line1: z.string().min(5, 'Address is required').max(200),
  city: z.string().min(1, 'City is required').max(100),
  country: z.string().min(2, 'Country is required').max(5),
  property_type: z.enum(['house', 'apartment', 'villa', 'condo', 'townhouse', 'studio', 'other']),
})

type PropertyFormValues = z.infer<typeof propertySchema>

const PROPERTY_TYPES: Array<{ value: PropertyType; label: string; icon: React.ComponentType<{className?: string}> }> = [
  { value: 'house', label: 'House', icon: Home },
  { value: 'apartment', label: 'Apartment', icon: Building2 },
  { value: 'villa', label: 'Villa', icon: Hotel },
  { value: 'other', label: 'Other', icon: Building2 },
]

interface AddPropertyStepProps {
  userId: string
  onNext: () => void
  onBack: () => void
}

export function AddPropertyStep({ userId, onNext, onBack }: AddPropertyStepProps) {
  const [serverError, setServerError] = React.useState<string | null>(null)

  const {
    register,
    handleSubmit,
    watch,
    setValue,
    formState: { errors, isSubmitting },
  } = useForm<PropertyFormValues>({
    resolver: zodResolver(propertySchema),
    defaultValues: {
      property_type: 'house',
      country: 'RO',
    },
  })

  const selectedType = watch('property_type')

  async function onSubmit(values: PropertyFormValues) {
    setServerError(null)
    const supabase = createClient()

    // Create the property
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: property, error: propertyError } = await (supabase as any).from('properties').insert({
      name: values.name,
      address_line1: values.address_line1,
      city: values.city,
      country: values.country,
      property_type: values.property_type,
      timezone: 'UTC',
      currency: 'EUR',
      is_active: true,
      metadata: {},
    }).select().single() as { data: Property | null; error: { message: string } | null }

    if (propertyError || !property) {
      setServerError(propertyError?.message ?? 'Failed to create property')
      return
    }

    // Add the user as owner
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error: memberError } = await (supabase as any).from('property_members').insert({
      property_id: property.id,
      user_id: userId,
      role: 'owner',
      status: 'active',
      permissions: {},
    }) as { error: { message: string } | null }

    if (memberError) {
      setServerError(memberError.message)
      return
    }

    onNext()
  }

  return (
    <div className="flex flex-1 flex-col px-4 py-6 max-w-sm mx-auto w-full">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-foreground">Add Your Property</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Let&apos;s start with your home&apos;s details
        </p>
      </div>

      <form onSubmit={handleSubmit(onSubmit)} className="flex flex-1 flex-col gap-5">
        {serverError && (
          <div className="rounded-lg border border-destructive/30 bg-destructive/10 px-4 py-3" role="alert">
            <p className="text-sm text-destructive">{serverError}</p>
          </div>
        )}

        <Input
          label="Property nickname"
          placeholder='e.g., "My Home", "Beach House"'
          hint="A friendly name to identify this property"
          error={errors.name?.message}
          {...register('name')}
        />

        <Input
          label="Address"
          placeholder="Start typing your address"
          error={errors.address_line1?.message}
          {...register('address_line1')}
        />

        <div className="grid grid-cols-2 gap-3">
          <Input
            label="City"
            placeholder="e.g., Cluj-Napoca"
            error={errors.city?.message}
            {...register('city')}
          />
          <Input
            label="Country"
            placeholder="e.g., RO"
            error={errors.country?.message}
            {...register('country')}
          />
        </div>

        {/* Property Type */}
        <div className="flex flex-col gap-2">
          <label className="text-sm font-medium text-[var(--text-secondary)]">
            Property type
          </label>
          <div className="grid grid-cols-2 gap-2">
            {PROPERTY_TYPES.map((type) => (
              <button
                key={type.value}
                type="button"
                onClick={() => setValue('property_type', type.value)}
                className={cn(
                  'flex items-center gap-2.5 rounded-xl px-3 py-3',
                  'transition-all duration-fast focus-ring',
                  selectedType === type.value
                    ? 'glass-standard text-foreground'
                    : 'glass-light text-muted-foreground hover:text-foreground'
                )}
              >
                <type.icon className="h-4 w-4 shrink-0" />
                <span className="text-sm font-medium">{type.label}</span>
              </button>
            ))}
          </div>
        </div>

        {/* Spacer */}
        <div className="flex-1" />

        {/* Actions */}
        <div className="flex gap-3">
          <Button type="button" variant="ghost" size="lg" onClick={onBack}>
            Back
          </Button>
          <Button type="submit" size="lg" fullWidth loading={isSubmitting}>
            Continue
          </Button>
        </div>
      </form>
    </div>
  )
}
