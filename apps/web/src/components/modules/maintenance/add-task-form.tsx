'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Camera, Plus, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { createClient } from '@/lib/supabase/client'
import type { Room } from '@/lib/supabase/types'

const CATEGORIES = ['maintenance', 'repair', 'inspection', 'cleaning', 'upgrade', 'administrative', 'other'] as const
const PRIORITIES = ['critical', 'high', 'medium', 'low'] as const

const RECURRENCE_RULES = [
  { value: 'daily', label: 'Daily' },
  { value: 'weekly', label: 'Weekly' },
  { value: 'monthly', label: 'Monthly' },
  { value: 'every_3_months', label: 'Every 3 months' },
  { value: 'every_6_months', label: 'Every 6 months' },
  { value: 'yearly', label: 'Yearly' },
] as const

const schema = z.object({
  title: z.string().min(1, 'Title is required').max(200),
  description: z.string().max(2000).optional(),
  category: z.enum(CATEGORIES),
  priority: z.enum(PRIORITIES),
  due_date: z.string().optional(),
  estimated_cost: z.coerce.number().positive().optional(),
  estimated_hours: z.coerce.number().positive().optional(),
  contractor_name: z.string().max(100).optional(),
  contractor_phone: z.string().max(50).optional(),
  contractor_email: z.string().email().optional().or(z.literal('')),
  is_recurring: z.boolean(),
  recurrence_rule: z.string().max(50).optional(),
  notes: z.string().max(2000).optional(),
  room_id: z.string().optional(),
  inventory_item_id: z.string().optional(),
  assigned_to_member_id: z.string().optional(),
  tags: z.string().optional(),
})

type FormValues = z.infer<typeof schema>
type ChecklistItem = { text: string; done: boolean }

interface SlimMember { id: string; display_name: string | null; nickname: string | null }
interface SlimInventoryItem { id: string; name: string }

interface AddTaskFormProps {
  propertyId: string
  userId: string
  rooms?: Pick<Room, 'id' | 'name' | 'floor'>[]
  members?: SlimMember[]
  inventoryItems?: SlimInventoryItem[]
}

export function AddTaskForm({
  propertyId,
  userId,
  rooms = [],
  members = [],
  inventoryItems = [],
}: AddTaskFormProps) {
  const router = useRouter()
  const [serverError, setServerError] = React.useState<string | null>(null)
  const [beforePhotos, setBeforePhotos] = React.useState<string[]>([])
  const [checklist, setChecklist] = React.useState<ChecklistItem[]>([])
  const [newChecklistItem, setNewChecklistItem] = React.useState('')
  const [uploading, setUploading] = React.useState(false)
  const beforeFileRef = React.useRef<HTMLInputElement>(null)

  const {
    register,
    handleSubmit,
    watch,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { category: 'maintenance', priority: 'medium', is_recurring: false },
  })

  const isRecurring = watch('is_recurring')
  const contractorName = watch('contractor_name')

  async function uploadPhoto(file: File): Promise<string | null> {
    const supabase = createClient()
    const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')
    const path = `maintenance-photos/${propertyId}/${Date.now()}-${safeName}`
    const { error } = await supabase.storage.from('documents').upload(path, file, { upsert: false })
    if (error) return null
    const { data: { publicUrl } } = supabase.storage.from('documents').getPublicUrl(path)
    return publicUrl
  }

  async function handleBeforePhotos(e: React.ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? [])
    if (!files.length) return
    setUploading(true)
    const urls = await Promise.all(files.map(uploadPhoto))
    setBeforePhotos((prev) => [...prev, ...(urls.filter(Boolean) as string[])])
    setUploading(false)
    if (beforeFileRef.current) beforeFileRef.current.value = ''
  }

  function addChecklistItem() {
    if (!newChecklistItem.trim()) return
    setChecklist((prev) => [...prev, { text: newChecklistItem.trim(), done: false }])
    setNewChecklistItem('')
  }

  function removeChecklistItem(i: number) {
    setChecklist((prev) => prev.filter((_, idx) => idx !== i))
  }

  async function onSubmit(values: FormValues) {
    setServerError(null)
    const supabase = createClient()
    const tags = values.tags ? values.tags.split(',').map((t) => t.trim()).filter(Boolean) : []

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error } = await (supabase as any).from('maintenance_tasks').insert({
      property_id: propertyId,
      title: values.title,
      description: values.description ?? null,
      category: values.category,
      priority: values.priority,
      status: 'pending',
      due_date: values.due_date ?? null,
      estimated_cost: values.estimated_cost ?? null,
      estimated_hours: values.estimated_hours ?? null,
      contractor_name: values.contractor_name ?? null,
      contractor_phone: values.contractor_phone ?? null,
      contractor_email: values.contractor_email || null,
      notes: values.notes ?? null,
      created_by: userId,
      is_recurring: values.is_recurring,
      recurrence_rule: values.is_recurring ? (values.recurrence_rule ?? 'monthly') : null,
      room_id: values.room_id || null,
      inventory_item_id: values.inventory_item_id || null,
      assigned_to_member_id: values.assigned_to_member_id || null,
      before_photo_urls: beforePhotos,
      after_photo_urls: [],
      checklist,
      tags,
    })

    if (error) {
      setServerError((error as { message: string }).message ?? 'Failed to create task')
      return
    }

    router.push('/maintenance')
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

      {(rooms.length > 0 || members.length > 0) && (
        <div className="grid grid-cols-2 gap-3">
          {rooms.length > 0 && (
            <div className="flex flex-col gap-2">
              <label className="text-sm font-medium text-[var(--text-secondary)]">Room</label>
              <select
                {...register('room_id')}
                className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
              >
                <option value="">None</option>
                {rooms.map((r) => (
                  <option key={r.id} value={r.id}>{r.name}</option>
                ))}
              </select>
            </div>
          )}
          {members.length > 0 && (
            <div className="flex flex-col gap-2">
              <label className="text-sm font-medium text-[var(--text-secondary)]">Assign to</label>
              <select
                {...register('assigned_to_member_id')}
                className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
              >
                <option value="">Unassigned</option>
                {members.map((m) => (
                  <option key={m.id} value={m.id}>{m.nickname ?? m.display_name ?? 'Member'}</option>
                ))}
              </select>
            </div>
          )}
        </div>
      )}

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
        <Input label="Contractor name" placeholder="Optional" {...register('contractor_name')} />
      </div>

      {contractorName && (
        <div className="grid grid-cols-2 gap-3">
          <Input label="Contractor phone" placeholder="+1 555 000 0000" {...register('contractor_phone')} />
          <Input label="Contractor email" type="email" placeholder="name@example.com" {...register('contractor_email')} />
        </div>
      )}

      {inventoryItems.length > 0 && (
        <div className="flex flex-col gap-2">
          <label className="text-sm font-medium text-[var(--text-secondary)]">Linked inventory item</label>
          <select
            {...register('inventory_item_id')}
            className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
          >
            <option value="">None</option>
            {inventoryItems.map((item) => (
              <option key={item.id} value={item.id}>{item.name}</option>
            ))}
          </select>
        </div>
      )}

      {/* Checklist */}
      <div className="flex flex-col gap-3 rounded-xl border border-border glass-light px-4 py-3">
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Checklist</p>
        {checklist.map((item, i) => (
          <div key={i} className="flex items-center gap-2">
            <span className="flex-1 text-sm text-foreground">{item.text}</span>
            <button
              type="button"
              onClick={() => removeChecklistItem(i)}
              className="text-muted-foreground hover:text-destructive transition-colors"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        ))}
        <div className="flex gap-2">
          <input
            value={newChecklistItem}
            onChange={(e) => setNewChecklistItem(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addChecklistItem() } }}
            placeholder="Add a step…"
            className="flex-1 h-9 rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
          />
          <Button type="button" variant="secondary" size="sm" onClick={addChecklistItem} disabled={!newChecklistItem.trim()}>
            <Plus className="h-3.5 w-3.5" />
          </Button>
        </div>
      </div>

      {/* Before photos */}
      <div className="flex flex-col gap-3">
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Before photos</p>
        {beforePhotos.length > 0 && (
          <div className="flex gap-2 flex-wrap">
            {beforePhotos.map((url, i) => (
              <div key={url} className="relative">
                <img src={url} alt={`Before ${i + 1}`} className="h-20 w-20 rounded-xl object-cover border border-border" />
                <button
                  type="button"
                  onClick={() => setBeforePhotos((p) => p.filter((_, idx) => idx !== i))}
                  className="absolute -top-1.5 -right-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-destructive text-white"
                >
                  <X className="h-3 w-3" />
                </button>
              </div>
            ))}
          </div>
        )}
        <input ref={beforeFileRef} type="file" accept="image/*" multiple onChange={handleBeforePhotos} className="hidden" />
        <Button
          type="button"
          variant="secondary"
          size="sm"
          onClick={() => beforeFileRef.current?.click()}
          loading={uploading}
          className="self-start"
        >
          <Camera className="h-3.5 w-3.5" />
          Add photo
        </Button>
      </div>

      <Input
        label="Tags"
        placeholder="hvac, plumbing, urgent (comma-separated)"
        {...register('tags')}
      />

      {/* Recurring task */}
      <div className="flex flex-col gap-3 rounded-xl border border-border glass-light px-4 py-3">
        <label className="flex items-center gap-3 cursor-pointer">
          <input
            type="checkbox"
            {...register('is_recurring')}
            className="h-4 w-4 rounded border-border accent-primary"
          />
          <span className="text-sm font-medium text-foreground">Recurring task</span>
        </label>
        {isRecurring && (
          <div className="flex flex-col gap-2">
            <label className="text-xs text-muted-foreground uppercase tracking-wider">Repeat</label>
            <select
              {...register('recurrence_rule')}
              defaultValue="monthly"
              className="h-10 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
            >
              {RECURRENCE_RULES.map((r) => (
                <option key={r.value} value={r.value}>{r.label}</option>
              ))}
            </select>
          </div>
        )}
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
          Create Task
        </Button>
      </div>
    </form>
  )
}
