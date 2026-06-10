'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { createClient } from '@/lib/supabase/client'
import type { InventoryItem } from '@/lib/supabase/types'

const CATEGORIES = ['Appliances', 'Electronics', 'Furniture', 'Tools', 'HVAC', 'Plumbing', 'Lighting', 'Other']
const CONDITIONS = ['excellent', 'good', 'fair', 'poor', 'broken'] as const

const schema = z.object({
  name: z.string().min(1, 'Name is required').max(200),
  brand: z.string().max(100).optional(),
  model: z.string().max(100).optional(),
  category: z.string().max(100).optional(),
  condition: z.enum(CONDITIONS).optional(),
  purchase_date: z.string().optional(),
  purchase_price: z.coerce.number().positive().optional().or(z.literal('')),
  warranty_expires: z.string().optional(),
  serial_number: z.string().max(100).optional(),
  barcode: z.string().max(200).optional(),
  notes: z.string().max(2000).optional(),
})

type FormValues = z.infer<typeof schema>

export function EditInventoryItemForm({ item }: { item: InventoryItem }) {
  const router = useRouter()
  const [serverError, setServerError] = React.useState<string | null>(null)

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      name: item.name,
      brand: item.brand ?? '',
      model: item.model ?? '',
      category: item.category ?? '',
      condition: item.condition ?? undefined,
      purchase_date: item.purchase_date ?? '',
      purchase_price: item.purchase_price ?? undefined,
      warranty_expires: item.warranty_expires ?? '',
      serial_number: item.serial_number ?? '',
      barcode: item.barcode ?? '',
      notes: item.notes ?? '',
    },
  })

  async function onSubmit(values: FormValues) {
    setServerError(null)
    const supabase = createClient()

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error } = await (supabase as any).from('inventory_items').update({
      name: values.name,
      brand: values.brand || null,
      model: values.model || null,
      category: values.category || null,
      condition: values.condition ?? null,
      purchase_date: values.purchase_date || null,
      purchase_price: values.purchase_price || null,
      warranty_expires: values.warranty_expires || null,
      serial_number: values.serial_number || null,
      barcode: values.barcode || null,
      notes: values.notes || null,
    }).eq('id', item.id)

    if (error) {
      setServerError((error as { message: string }).message ?? 'Failed to update item')
      return
    }

    router.push(`/inventory/${item.id}`)
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
        label="Item name *"
        placeholder='e.g. "Washing Machine", "Sofa"'
        error={errors.name?.message}
        {...register('name')}
      />

      <div className="grid grid-cols-2 gap-3">
        <Input label="Brand" placeholder="e.g. Samsung" {...register('brand')} />
        <Input label="Model" placeholder="e.g. WF45T" {...register('model')} />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div className="flex flex-col gap-2">
          <label className="text-sm font-medium text-[var(--text-secondary)]">Category</label>
          <select
            {...register('category')}
            className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
          >
            <option value="">Select…</option>
            {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        </div>
        <div className="flex flex-col gap-2">
          <label className="text-sm font-medium text-[var(--text-secondary)]">Condition</label>
          <select
            {...register('condition')}
            className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 capitalize"
          >
            <option value="">Select…</option>
            {CONDITIONS.map((c) => <option key={c} value={c} className="capitalize">{c}</option>)}
          </select>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Input label="Purchase date" type="date" {...register('purchase_date')} />
        <Input
          label="Purchase price (€)"
          type="number"
          placeholder="e.g. 499"
          inputMode="decimal"
          {...register('purchase_price')}
        />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Input label="Warranty expires" type="date" {...register('warranty_expires')} />
        <Input label="Serial number" placeholder="Optional" {...register('serial_number')} />
      </div>

      <Input label="Barcode / EAN" placeholder="Scan with M-SCAN™ or enter manually" {...register('barcode')} />

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
