'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { createClient } from '@/lib/supabase/client'
import type { Property } from '@/lib/supabase/types'

const schema = z.object({
  name: z.string().min(1, 'Property name is required').max(100),
  address_line1: z.string().min(5, 'Address is required').max(200),
  address_line2: z.string().max(200).optional(),
  city: z.string().min(1, 'City is required').max(100),
  state_province: z.string().max(100).optional(),
  postal_code: z.string().max(20).optional(),
  country: z.string().min(2).max(5),
  property_type: z.enum(['house', 'apartment', 'villa', 'condo', 'townhouse', 'studio', 'other']),
  size_sqm: z.coerce.number().positive().optional(),
  year_built: z.coerce.number().min(1800).max(new Date().getFullYear()).optional(),
  num_rooms: z.coerce.number().int().positive().optional(),
  num_bathrooms: z.coerce.number().int().positive().optional(),
})

type FormValues = z.infer<typeof schema>

const PROPERTY_TYPES = [
  { value: 'house', label: 'House' },
  { value: 'apartment', label: 'Apartment' },
  { value: 'villa', label: 'Villa' },
  { value: 'condo', label: 'Condo' },
  { value: 'townhouse', label: 'Townhouse' },
  { value: 'studio', label: 'Studio' },
  { value: 'other', label: 'Other' },
] as const

interface AddPropertyFormProps {
  userId: string
}

export function AddPropertyForm({ userId }: AddPropertyFormProps) {
  const router = useRouter()
  const [serverError, setServerError] = React.useState<string | null>(null)

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { property_type: 'house', country: 'RO' },
  })

  async function onSubmit(values: FormValues) {
    setServerError(null)
    const supabase = createClient()

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: property, error } = await (supabase as any).from('properties').insert({
      name: values.name,
      address_line1: values.address_line1,
      address_line2: values.address_line2 ?? null,
      city: values.city,
      state_province: values.state_province ?? null,
      postal_code: values.postal_code ?? null,
      country: values.country,
      property_type: values.property_type,
      size_sqm: values.size_sqm ?? null,
      year_built: values.year_built ?? null,
      num_rooms: values.num_rooms ?? null,
      num_bathrooms: values.num_bathrooms ?? null,
      timezone: 'UTC',
      currency: 'EUR',
      is_active: true,
      metadata: {},
    }).select().single() as { data: Property | null; error: { message: string } | null }

    if (error || !property) {
      setServerError(error?.message ?? 'Failed to create property')
      return
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('property_members').insert({
      property_id: property.id,
      user_id: userId,
      role: 'owner',
      status: 'active',
      permissions: {},
    })

    router.push(`/property/${property.id}`)
    router.refresh()
  }

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-5">
      {serverError && (
        <div className="rounded-xl border border-destructive/30 bg-destructive/10 px-4 py-3" role="alert">
          <p className="text-sm text-destructive">{serverError}</p>
        </div>
      )}

      <Input
        label="Property nickname *"
        placeholder='e.g. "My Home", "Beach House"'
        error={errors.name?.message}
        {...register('name')}
      />

      <Input
        label="Address *"
        placeholder="Street address"
        error={errors.address_line1?.message}
        {...register('address_line1')}
      />

      <Input
        label="Address line 2"
        placeholder="Apartment, suite, etc."
        {...register('address_line2')}
      />

      <div className="grid grid-cols-2 gap-3">
        <Input
          label="City *"
          placeholder="e.g. Cluj-Napoca"
          error={errors.city?.message}
          {...register('city')}
        />
        <Input
          label="Postal code"
          placeholder="e.g. 400001"
          {...register('postal_code')}
        />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Input
          label="State / Province"
          placeholder="e.g. Cluj"
          {...register('state_province')}
        />
        <Input
          label="Country *"
          placeholder="e.g. RO"
          error={errors.country?.message}
          {...register('country')}
        />
      </div>

      <div className="flex flex-col gap-2">
        <label className="text-sm font-medium text-[var(--text-secondary)]">
          Property type
        </label>
        <select
          {...register('property_type')}
          className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
        >
          {PROPERTY_TYPES.map((t) => (
            <option key={t.value} value={t.value}>{t.label}</option>
          ))}
        </select>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Input
          label="Size (m²)"
          type="number"
          placeholder="e.g. 120"
          inputMode="numeric"
          {...register('size_sqm')}
        />
        <Input
          label="Year built"
          type="number"
          placeholder="e.g. 2005"
          inputMode="numeric"
          {...register('year_built')}
        />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Input
          label="Rooms"
          type="number"
          placeholder="e.g. 3"
          inputMode="numeric"
          {...register('num_rooms')}
        />
        <Input
          label="Bathrooms"
          type="number"
          placeholder="e.g. 2"
          inputMode="numeric"
          {...register('num_bathrooms')}
        />
      </div>

      <div className="flex gap-3 pt-2">
        <Button
          type="button"
          variant="ghost"
          size="lg"
          onClick={() => router.back()}
        >
          Cancel
        </Button>
        <Button type="submit" size="lg" fullWidth loading={isSubmitting}>
          Add Property
        </Button>
      </div>
    </form>
  )
}
