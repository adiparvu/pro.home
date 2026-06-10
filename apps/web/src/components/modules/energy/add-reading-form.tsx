'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { createClient } from '@/lib/supabase/client'
import type { MeterType, EnergyUnit } from '@/lib/supabase/types'

const METER_TYPES: { value: MeterType; label: string }[] = [
  { value: 'electricity', label: 'Electricity' },
  { value: 'gas', label: 'Gas' },
  { value: 'water', label: 'Water' },
  { value: 'solar', label: 'Solar' },
  { value: 'district_heating', label: 'District Heating' },
  { value: 'other', label: 'Other' },
]

const ENERGY_UNITS: { value: EnergyUnit; label: string }[] = [
  { value: 'kWh', label: 'kWh' },
  { value: 'm3', label: 'm³' },
  { value: 'L', label: 'L' },
  { value: 'GJ', label: 'GJ' },
  { value: 'other', label: 'Other' },
]

const DEFAULT_UNIT: Record<MeterType, EnergyUnit> = {
  electricity: 'kWh',
  gas: 'm3',
  water: 'm3',
  solar: 'kWh',
  district_heating: 'GJ',
  other: 'kWh',
}

const schema = z.object({
  meter_type: z.enum(['electricity', 'gas', 'water', 'solar', 'district_heating', 'other'] as const),
  reading_date: z.string().min(1, 'Date is required'),
  reading_value: z.coerce.number({ required_error: 'Reading value is required' }),
  unit: z.enum(['kWh', 'm3', 'L', 'GJ', 'other'] as const),
  cost: z.coerce.number().min(0).optional().or(z.literal('')),
  cost_currency: z.string().max(10).optional(),
  provider: z.string().max(100).optional(),
  meter_id: z.string().max(100).optional(),
  notes: z.string().max(500).optional(),
})

type FormValues = z.infer<typeof schema>

interface AddReadingFormProps {
  propertyId: string
  userId: string
}

export function AddReadingForm({ propertyId, userId }: AddReadingFormProps) {
  const router = useRouter()
  const [serverError, setServerError] = React.useState<string | null>(null)

  const today = new Date().toISOString().split('T')[0]

  const { register, handleSubmit, watch, setValue, formState: { errors, isSubmitting } } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      meter_type: 'electricity',
      reading_date: today,
      unit: 'kWh',
      cost_currency: 'EUR',
    },
  })

  const meterType = watch('meter_type')

  React.useEffect(() => {
    setValue('unit', DEFAULT_UNIT[meterType as MeterType] ?? 'kWh')
  }, [meterType, setValue])

  async function onSubmit(values: FormValues) {
    setServerError(null)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error } = await (supabase as any).from('energy_readings').insert({
      property_id: propertyId,
      meter_type: values.meter_type,
      reading_date: values.reading_date,
      reading_value: values.reading_value,
      unit: values.unit,
      cost: values.cost || null,
      cost_currency: values.cost ? (values.cost_currency ?? 'EUR') : null,
      provider: values.provider ?? null,
      meter_id: values.meter_id ?? null,
      notes: values.notes ?? null,
      created_by: userId,
    })

    if (error) {
      setServerError((error as { message: string }).message ?? 'Failed to save reading')
      return
    }

    router.push('/energy')
    router.refresh()
  }

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-5">
      {serverError && (
        <div className="rounded-xl border border-destructive/30 bg-destructive/10 px-4 py-3" role="alert">
          <p className="text-sm text-destructive">{serverError}</p>
        </div>
      )}

      <div className="flex flex-col gap-2">
        <label className="text-sm font-medium text-[var(--text-secondary)]">Meter type</label>
        <select
          {...register('meter_type')}
          className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
        >
          {METER_TYPES.map((t) => (
            <option key={t.value} value={t.value}>{t.label}</option>
          ))}
        </select>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Input
          label="Reading value *"
          type="number"
          step="any"
          placeholder="e.g. 12450"
          inputMode="decimal"
          error={errors.reading_value?.message}
          {...register('reading_value')}
        />
        <div className="flex flex-col gap-2">
          <label className="text-sm font-medium text-[var(--text-secondary)]">Unit</label>
          <select
            {...register('unit')}
            className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
          >
            {ENERGY_UNITS.map((u) => (
              <option key={u.value} value={u.value}>{u.label}</option>
            ))}
          </select>
        </div>
      </div>

      <Input
        label="Reading date *"
        type="date"
        error={errors.reading_date?.message}
        {...register('reading_date')}
      />

      <div className="grid grid-cols-2 gap-3">
        <Input
          label="Cost (optional)"
          type="number"
          step="any"
          placeholder="e.g. 85.50"
          inputMode="decimal"
          {...register('cost')}
        />
        <Input label="Currency" placeholder="EUR" {...register('cost_currency')} />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Input label="Provider" placeholder="e.g. EDF, Vattenfall" {...register('provider')} />
        <Input label="Meter ID" placeholder="Optional" {...register('meter_id')} />
      </div>

      <div className="flex flex-col gap-2">
        <label className="text-sm font-medium text-[var(--text-secondary)]">Notes</label>
        <textarea
          {...register('notes')}
          rows={2}
          placeholder="Any notes about this reading…"
          className="w-full rounded-xl border border-border glass-light px-3 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 resize-none"
        />
      </div>

      <div className="flex gap-3 pt-2">
        <Button type="button" variant="ghost" size="lg" onClick={() => router.back()}>
          Cancel
        </Button>
        <Button type="submit" size="lg" fullWidth loading={isSubmitting}>
          Save Reading
        </Button>
      </div>
    </form>
  )
}
