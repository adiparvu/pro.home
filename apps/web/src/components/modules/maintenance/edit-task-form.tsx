'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { createClient } from '@/lib/supabase/client'
import type { MaintenanceTask } from '@/lib/supabase/types'

const CATEGORIES = ['maintenance', 'repair', 'inspection', 'cleaning', 'upgrade', 'administrative', 'other'] as const
const PRIORITIES = ['critical', 'high', 'medium', 'low'] as const

const schema = z.object({
  title: z.string().min(1, 'Title is required').max(200),
  description: z.string().max(2000).optional(),
  category: z.enum(CATEGORIES),
  priority: z.enum(PRIORITIES),
  due_date: z.string().optional(),
  estimated_cost: z.coerce.number().positive().optional().or(z.literal('')),
  estimated_hours: z.coerce.number().positive().optional().or(z.literal('')),
  contractor_name: z.string().max(100).optional(),
  notes: z.string().max(2000).optional(),
})

type FormValues = z.infer<typeof schema>

export function EditTaskForm({ task }: { task: MaintenanceTask }) {
  const router = useRouter()
  const [serverError, setServerError] = React.useState<string | null>(null)

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      title: task.title,
      description: task.description ?? '',
      category: task.category as typeof CATEGORIES[number],
      priority: task.priority as typeof PRIORITIES[number],
      due_date: task.due_date ?? '',
      estimated_cost: task.estimated_cost ?? undefined,
      estimated_hours: task.estimated_hours ?? undefined,
      contractor_name: task.contractor_name ?? '',
      notes: task.notes ?? '',
    },
  })

  async function onSubmit(values: FormValues) {
    setServerError(null)
    const supabase = createClient()

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error } = await (supabase as any).from('maintenance_tasks').update({
      title: values.title,
      description: values.description || null,
      category: values.category,
      priority: values.priority,
      due_date: values.due_date || null,
      estimated_cost: values.estimated_cost || null,
      estimated_hours: values.estimated_hours || null,
      contractor_name: values.contractor_name || null,
      notes: values.notes || null,
    }).eq('id', task.id)

    if (error) {
      setServerError((error as { message: string }).message ?? 'Failed to update task')
      return
    }

    router.push(`/maintenance/${task.id}`)
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
        label="Task title *"
        placeholder='e.g. "Replace HVAC filter", "Fix leaking faucet"'
        error={errors.title?.message}
        {...register('title')}
      />

      <div className="flex flex-col gap-2">
        <label className="text-sm font-medium text-[var(--text-secondary)]">Description</label>
        <textarea
          {...register('description')}
          rows={3}
          placeholder="What needs to be done?"
          className="w-full rounded-xl border border-border glass-light px-3 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 resize-none"
        />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div className="flex flex-col gap-2">
          <label className="text-sm font-medium text-[var(--text-secondary)]">Category</label>
          <select
            {...register('category')}
            className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 capitalize"
          >
            {CATEGORIES.map((c) => (
              <option key={c} value={c} className="capitalize">{c}</option>
            ))}
          </select>
        </div>
        <div className="flex flex-col gap-2">
          <label className="text-sm font-medium text-[var(--text-secondary)]">Priority</label>
          <select
            {...register('priority')}
            className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 capitalize"
          >
            {PRIORITIES.map((p) => (
              <option key={p} value={p} className="capitalize">{p}</option>
            ))}
          </select>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Input label="Due date" type="date" {...register('due_date')} />
        <Input
          label="Estimated cost (€)"
          type="number"
          placeholder="e.g. 150"
          inputMode="decimal"
          {...register('estimated_cost')}
        />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Input
          label="Estimated hours"
          type="number"
          placeholder="e.g. 2"
          inputMode="decimal"
          {...register('estimated_hours')}
        />
        <Input
          label="Contractor name"
          placeholder="Optional"
          {...register('contractor_name')}
        />
      </div>

      <div className="flex flex-col gap-2">
        <label className="text-sm font-medium text-[var(--text-secondary)]">Notes</label>
        <textarea
          {...register('notes')}
          rows={3}
          placeholder="Any additional details…"
          className="w-full rounded-xl border border-border glass-light px-3 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 resize-none"
        />
      </div>

      <div className="flex gap-3 pt-2">
        <Button type="button" variant="ghost" size="lg" onClick={() => router.back()}>
          Cancel
        </Button>
        <Button type="submit" size="lg" fullWidth loading={isSubmitting}>
          Save Changes
        </Button>
      </div>
    </form>
  )
}
