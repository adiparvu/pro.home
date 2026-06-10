'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import type { GardenZone, GardenPlant, GardenTaskType } from '@/lib/supabase/types'

const schema = z.object({
  title: z.string().min(1, 'Title is required').max(200),
  task_type: z.enum(['watering', 'fertilizing', 'pruning', 'harvesting', 'planting', 'pest_control', 'repotting', 'weeding', 'general']),
  plant_id: z.string().optional(),
  zone_id: z.string().optional(),
  due_date: z.string().optional(),
  is_recurring: z.boolean(),
  recurrence_rule: z.string().max(100).optional(),
  notes: z.string().max(1000).optional(),
})

type FormValues = z.infer<typeof schema>

const TASK_TYPES: { value: GardenTaskType; label: string }[] = [
  { value: 'watering', label: 'Watering' },
  { value: 'fertilizing', label: 'Fertilizing' },
  { value: 'pruning', label: 'Pruning' },
  { value: 'harvesting', label: 'Harvesting' },
  { value: 'planting', label: 'Planting' },
  { value: 'pest_control', label: 'Pest control' },
  { value: 'repotting', label: 'Repotting' },
  { value: 'weeding', label: 'Weeding' },
  { value: 'general', label: 'General' },
]

interface AddGardenTaskFormProps {
  propertyId: string
  zones: GardenZone[]
  plants: GardenPlant[]
}

export function AddGardenTaskForm({ propertyId, zones, plants }: AddGardenTaskFormProps) {
  const router = useRouter()
  const [saving, setSaving] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)

  const { register, handleSubmit, watch, formState: { errors } } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { task_type: 'general', is_recurring: false },
  })

  const isRecurring = watch('is_recurring')

  async function onSubmit(data: FormValues) {
    setSaving(true); setError(null)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { error: e } = await (supabase as any).from('garden_tasks').insert({
        property_id: propertyId,
        plant_id: data.plant_id || null,
        zone_id: data.zone_id || null,
        title: data.title,
        task_type: data.task_type,
        status: 'pending',
        due_date: data.due_date || null,
        is_recurring: data.is_recurring,
        recurrence_rule: data.is_recurring ? (data.recurrence_rule || null) : null,
        notes: data.notes || null,
      })
      if (e) throw e
      router.push('/garden'); router.refresh()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save task')
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
        <label className={labelCls}>Task title *</label>
        <input {...register('title')} placeholder="e.g. Water the tomatoes" className={inputCls} />
        {errors.title && <p className={errorCls}>{errors.title.message}</p>}
      </div>

      <div className="flex flex-col gap-1.5">
        <label className={labelCls}>Task type</label>
        <select {...register('task_type')} className={selectCls}>
          {TASK_TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
        </select>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div className="flex flex-col gap-1.5">
          <label className={labelCls}>Plant (optional)</label>
          <select {...register('plant_id')} className={selectCls}>
            <option value="">Any / all</option>
            {plants.filter((p) => p.status !== 'removed').map((p) => (
              <option key={p.id} value={p.id}>{p.name}</option>
            ))}
          </select>
        </div>
        <div className="flex flex-col gap-1.5">
          <label className={labelCls}>Zone (optional)</label>
          <select {...register('zone_id')} className={selectCls}>
            <option value="">Any / all</option>
            {zones.map((z) => <option key={z.id} value={z.id}>{z.name}</option>)}
          </select>
        </div>
      </div>

      <div className="flex flex-col gap-1.5">
        <label className={labelCls}>Due date</label>
        <input {...register('due_date')} type="date" className={inputCls} />
      </div>

      <div className="flex items-center gap-3">
        <input
          {...register('is_recurring')}
          id="is_recurring"
          type="checkbox"
          className="h-4 w-4 rounded border border-border accent-primary"
        />
        <label htmlFor="is_recurring" className="text-sm text-foreground cursor-pointer">Recurring task</label>
      </div>

      {isRecurring && (
        <div className="flex flex-col gap-1.5">
          <label className={labelCls}>Recurrence rule</label>
          <input {...register('recurrence_rule')} placeholder="e.g. FREQ=WEEKLY;BYDAY=MO,WE" className={inputCls} />
        </div>
      )}

      <div className="flex flex-col gap-1.5">
        <label className={labelCls}>Notes</label>
        <textarea {...register('notes')} rows={3} placeholder="Additional notes…" className="w-full rounded-xl border border-border glass-light px-4 py-2.5 text-sm text-foreground placeholder:text-muted-foreground resize-none focus:outline-none focus:ring-2 focus:ring-primary/60" />
      </div>

      <Button type="submit" variant="primary" loading={saving} className="mt-2">Save task</Button>
    </form>
  )
}
