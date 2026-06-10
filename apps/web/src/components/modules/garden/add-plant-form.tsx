'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { X } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import type { GardenPlant, GardenZone, PlantStatus } from '@/lib/supabase/types'

const schema = z.object({
  name: z.string().min(1, 'Name is required').max(120),
  species: z.string().max(120).optional(),
  common_name: z.string().max(120).optional(),
  zone_id: z.string().optional(),
  status: z.enum(['healthy', 'needs_attention', 'dormant', 'harvested']),
  planted_date: z.string().optional(),
  watering_frequency_days: z.number().int().min(1).max(365).nullable(),
  fertilizing_frequency_days: z.number().int().min(1).max(365).nullable(),
  sunlight_needs: z.enum(['full_sun', 'partial_shade', 'full_shade', 'shade', '']),
  notes: z.string().max(1000).optional(),
})

type FormValues = z.infer<typeof schema>

const STATUS_OPTIONS: { value: PlantStatus; label: string }[] = [
  { value: 'healthy', label: 'Healthy' },
  { value: 'needs_attention', label: 'Needs attention' },
  { value: 'dormant', label: 'Dormant' },
  { value: 'harvested', label: 'Harvested' },
]

interface AddPlantFormProps {
  propertyId: string
  userId: string
  zones: GardenZone[]
  plant?: GardenPlant
}

export function AddPlantForm({ propertyId, userId, zones, plant }: AddPlantFormProps) {
  const router = useRouter()
  const [tagInput, setTagInput] = React.useState('')
  const [tags, setTags] = React.useState<string[]>(plant?.tags ?? [])
  const [saving, setSaving] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)
  const isEdit = !!plant

  const { register, handleSubmit, formState: { errors } } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: plant
      ? {
          name: plant.name,
          species: plant.species ?? '',
          common_name: plant.common_name ?? '',
          zone_id: plant.zone_id ?? '',
          status: plant.status as Exclude<PlantStatus, 'removed'>,
          planted_date: plant.planted_date ?? '',
          watering_frequency_days: plant.watering_frequency_days,
          fertilizing_frequency_days: plant.fertilizing_frequency_days,
          sunlight_needs: (plant.sunlight_needs as FormValues['sunlight_needs']) ?? '',
          notes: plant.notes ?? '',
        }
      : { status: 'healthy', watering_frequency_days: null, fertilizing_frequency_days: null },
  })

  function addTag(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'Enter' || e.key === ',') {
      e.preventDefault()
      const val = tagInput.trim()
      if (val && !tags.includes(val) && tags.length < 10) setTags((prev) => [...prev, val])
      setTagInput('')
    }
  }

  async function onSubmit(data: FormValues) {
    setSaving(true); setError(null)
    try {
      const supabase = createClient()
      if (isEdit && plant) {
        const payload = {
          zone_id: data.zone_id || null,
          name: data.name,
          species: data.species || null,
          common_name: data.common_name || null,
          status: data.status,
          planted_date: data.planted_date || null,
          watering_frequency_days: data.watering_frequency_days,
          fertilizing_frequency_days: data.fertilizing_frequency_days,
          sunlight_needs: data.sunlight_needs || null,
          notes: data.notes || null,
          tags,
        }
        // If watering frequency changed, recalculate next_watering
        if (data.watering_frequency_days && data.watering_frequency_days !== plant.watering_frequency_days) {
          const nextWatering = new Date(Date.now() + data.watering_frequency_days * 86400000).toISOString().split('T')[0] ?? null
          Object.assign(payload, { next_watering: nextWatering })
        }
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { error: e } = await (supabase as any).from('garden_plants').update(payload).eq('id', plant.id)
        if (e) throw e
      } else {
        const today = new Date().toISOString().split('T')[0]
        const nextWatering = data.watering_frequency_days
          ? new Date(Date.now() + data.watering_frequency_days * 86400000).toISOString().split('T')[0]
          : null
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { error: e } = await (supabase as any).from('garden_plants').insert({
          property_id: propertyId,
          zone_id: data.zone_id || null,
          name: data.name,
          species: data.species || null,
          common_name: data.common_name || null,
          status: data.status,
          planted_date: data.planted_date || null,
          watering_frequency_days: data.watering_frequency_days,
          next_watering: data.watering_frequency_days ? nextWatering : null,
          last_watered: data.watering_frequency_days ? today : null,
          fertilizing_frequency_days: data.fertilizing_frequency_days,
          sunlight_needs: data.sunlight_needs || null,
          notes: data.notes || null,
          tags,
        })
        if (e) throw e
      }
      router.push('/garden'); router.refresh()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save plant')
    } finally { setSaving(false) }
  }

  const inputCls = 'h-11 w-full rounded-xl border border-border glass-light px-4 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60'
  const labelCls = 'text-xs text-muted-foreground'
  const errorCls = 'mt-1 text-xs text-destructive'
  const selectCls = 'h-11 w-full rounded-xl border border-border glass-light px-4 text-sm text-foreground bg-transparent focus:outline-none focus:ring-2 focus:ring-primary/60'

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 max-w-xl mx-auto">
      {error && (
        <div className="rounded-xl border border-destructive/30 bg-destructive/10 px-4 py-3 text-sm text-destructive">{error}</div>
      )}

      <div className="flex flex-col gap-1.5">
        <label className={labelCls}>Plant name *</label>
        <input {...register('name')} placeholder="e.g. Monstera" className={inputCls} />
        {errors.name && <p className={errorCls}>{errors.name.message}</p>}
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div className="flex flex-col gap-1.5">
          <label className={labelCls}>Species (botanical)</label>
          <input {...register('species')} placeholder="M. deliciosa" className={inputCls} />
        </div>
        <div className="flex flex-col gap-1.5">
          <label className={labelCls}>Common name</label>
          <input {...register('common_name')} placeholder="Swiss Cheese Plant" className={inputCls} />
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div className="flex flex-col gap-1.5">
          <label className={labelCls}>Zone</label>
          <select {...register('zone_id')} className={selectCls}>
            <option value="">No zone</option>
            {zones.map((z) => <option key={z.id} value={z.id}>{z.name}</option>)}
          </select>
        </div>
        <div className="flex flex-col gap-1.5">
          <label className={labelCls}>Status</label>
          <select {...register('status')} className={selectCls}>
            {STATUS_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
          </select>
        </div>
      </div>

      <div className="flex flex-col gap-1.5">
        <label className={labelCls}>Planted date</label>
        <input {...register('planted_date')} type="date" className={inputCls} />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div className="flex flex-col gap-1.5">
          <label className={labelCls}>Water every (days)</label>
          <input
            {...register('watering_frequency_days', { setValueAs: (v) => v === '' ? null : Number(v) })}
            type="number" min="1" max="365" placeholder="7"
            className={inputCls}
          />
        </div>
        <div className="flex flex-col gap-1.5">
          <label className={labelCls}>Fertilize every (days)</label>
          <input
            {...register('fertilizing_frequency_days', { setValueAs: (v) => v === '' ? null : Number(v) })}
            type="number" min="1" max="365" placeholder="30"
            className={inputCls}
          />
        </div>
      </div>

      <div className="flex flex-col gap-1.5">
        <label className={labelCls}>Sunlight needs</label>
        <select {...register('sunlight_needs')} className={selectCls}>
          <option value="">Not specified</option>
          <option value="full_sun">Full sun</option>
          <option value="partial_shade">Partial shade</option>
          <option value="full_shade">Full shade</option>
          <option value="shade">Shade</option>
        </select>
      </div>

      <div className="flex flex-col gap-1.5">
        <label className={labelCls}>Tags</label>
        <input value={tagInput} onChange={(e) => setTagInput(e.target.value)} onKeyDown={addTag} placeholder="Type a tag and press Enter" className={inputCls} />
        {tags.length > 0 && (
          <div className="flex flex-wrap gap-1.5 mt-1">
            {tags.map((tag) => (
              <span key={tag} className="flex items-center gap-1 rounded-full glass-light px-2.5 py-1 text-xs text-foreground">
                {tag}
                <button type="button" onClick={() => setTags((p) => p.filter((t) => t !== tag))} className="text-muted-foreground hover:text-foreground">
                  <X className="h-3 w-3" />
                </button>
              </span>
            ))}
          </div>
        )}
      </div>

      <div className="flex flex-col gap-1.5">
        <label className={labelCls}>Notes</label>
        <textarea {...register('notes')} rows={3} placeholder="Care notes, soil mix, special requirements…" className="w-full rounded-xl border border-border glass-light px-4 py-2.5 text-sm text-foreground placeholder:text-muted-foreground resize-none focus:outline-none focus:ring-2 focus:ring-primary/60" />
      </div>

      <Button type="submit" variant="primary" loading={saving} className="mt-2">
        {isEdit ? 'Update plant' : 'Save plant'}
      </Button>
    </form>
  )
}
