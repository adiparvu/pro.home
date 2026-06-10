'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Camera, X, Plus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { createClient } from '@/lib/supabase/client'

const CATEGORIES = ['Appliances', 'Electronics', 'Furniture', 'Tools', 'HVAC', 'Plumbing', 'Lighting', 'Safety', 'Other']
const CONDITIONS = ['excellent', 'good', 'fair', 'poor', 'broken'] as const

const schema = z.object({
  name: z.string().min(1, 'Name is required').max(200),
  brand: z.string().max(100).optional(),
  model: z.string().max(100).optional(),
  category: z.string().max(100).optional(),
  condition: z.enum(CONDITIONS).optional(),
  room_id: z.string().optional(),
  purchase_date: z.string().optional(),
  purchase_price: z.coerce.number().positive().optional(),
  current_value: z.coerce.number().min(0).optional(),
  warranty_expires: z.string().optional(),
  warranty_provider: z.string().max(200).optional(),
  manual_url: z.string().max(500).optional(),
  serial_number: z.string().max(100).optional(),
  barcode: z.string().max(200).optional(),
  tags: z.string().optional(),
  notes: z.string().max(2000).optional(),
})

type FormValues = z.infer<typeof schema>

interface AddInventoryItemFormProps {
  propertyId: string
  userId: string
  rooms?: { id: string; name: string; floor: number }[]
  initialBarcode?: string
}

export function AddInventoryItemForm({ propertyId, userId, rooms = [], initialBarcode }: AddInventoryItemFormProps) {
  const router = useRouter()
  const [serverError, setServerError] = React.useState<string | null>(null)
  const [photoUrls, setPhotoUrls] = React.useState<string[]>([])
  const [uploadingPhoto, setUploadingPhoto] = React.useState(false)
  const photoInputRef = React.useRef<HTMLInputElement>(null)

  const { register, handleSubmit, formState: { errors, isSubmitting } } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { barcode: initialBarcode ?? '' },
  })

  async function handlePhotoUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    setUploadingPhoto(true)
    const supabase = createClient()
    const path = `inventory-photos/${propertyId}/${Date.now()}-${file.name.replace(/[^a-z0-9.-]/gi, '_')}`
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error: storageError } = await (supabase as any).storage.from('documents').upload(path, file, { upsert: true, contentType: file.type })
    if (!storageError) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: urlData } = (supabase as any).storage.from('documents').getPublicUrl(path)
      setPhotoUrls((prev) => [...prev, (urlData as { publicUrl: string }).publicUrl])
    }
    setUploadingPhoto(false)
    if (photoInputRef.current) photoInputRef.current.value = ''
  }

  async function onSubmit(values: FormValues) {
    setServerError(null)
    const supabase = createClient()
    const tags = values.tags ? values.tags.split(',').map((t) => t.trim()).filter(Boolean) : []

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error } = await (supabase as any).from('inventory_items').insert({
      property_id: propertyId,
      room_id: values.room_id || null,
      name: values.name,
      brand: values.brand || null,
      model: values.model || null,
      category: values.category || null,
      condition: values.condition || null,
      purchase_date: values.purchase_date || null,
      purchase_price: values.purchase_price ?? null,
      purchase_currency: 'EUR',
      current_value: values.current_value ?? null,
      warranty_expires: values.warranty_expires || null,
      warranty_provider: values.warranty_provider || null,
      manual_url: values.manual_url || null,
      serial_number: values.serial_number || null,
      barcode: values.barcode || null,
      notes: values.notes || null,
      tags,
      photo_urls: photoUrls,
      added_by: userId,
      recall_active: false,
      qr_code: null,
      metadata: {},
    })

    if (error) {
      setServerError((error as { message: string }).message ?? 'Failed to add item')
      return
    }

    router.push('/inventory')
    router.refresh()
  }

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-5">
      {serverError && (
        <div className="rounded-xl border border-destructive/30 bg-destructive/10 px-4 py-3" role="alert">
          <p className="text-sm text-destructive">{serverError}</p>
        </div>
      )}

      {/* Photos */}
      <div className="flex flex-col gap-2">
        <label className="text-sm font-medium text-[var(--text-secondary)]">Photos</label>
        <div className="flex flex-wrap gap-2">
          {photoUrls.map((url, i) => (
            <div key={url} className="relative h-20 w-20 rounded-xl overflow-hidden border border-border">
              <img src={url} alt={`Photo ${i + 1}`} className="h-full w-full object-cover" />
              <button
                type="button"
                onClick={() => setPhotoUrls((prev) => prev.filter((_, j) => j !== i))}
                className="absolute top-0.5 right-0.5 flex h-5 w-5 items-center justify-center rounded-full bg-black/60 text-white"
                aria-label="Remove photo"
              >
                <X className="h-3 w-3" />
              </button>
            </div>
          ))}
          <button
            type="button"
            onClick={() => photoInputRef.current?.click()}
            disabled={uploadingPhoto}
            className="flex h-20 w-20 items-center justify-center rounded-xl border border-dashed border-border glass-light text-muted-foreground hover:text-foreground transition-colors focus-ring"
            aria-label="Add photo"
          >
            {uploadingPhoto ? (
              <span className="text-xs">…</span>
            ) : (
              <Camera className="h-5 w-5" />
            )}
          </button>
        </div>
        <input ref={photoInputRef} type="file" accept="image/jpeg,image/png,image/webp" onChange={handlePhotoUpload} className="hidden" />
      </div>

      <Input label="Item name *" placeholder='e.g. "Washing Machine", "Sofa"' error={errors.name?.message} {...register('name')} />

      <div className="grid grid-cols-2 gap-3">
        <Input label="Brand" placeholder="e.g. Samsung" {...register('brand')} />
        <Input label="Model" placeholder="e.g. WF45T" {...register('model')} />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div className="flex flex-col gap-2">
          <label className="text-sm font-medium text-[var(--text-secondary)]">Category</label>
          <select {...register('category')} className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60">
            <option value="">Select…</option>
            {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        </div>
        <div className="flex flex-col gap-2">
          <label className="text-sm font-medium text-[var(--text-secondary)]">Condition</label>
          <select {...register('condition')} className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground capitalize focus:outline-none focus:ring-2 focus:ring-primary/60">
            <option value="">Select…</option>
            {CONDITIONS.map((c) => <option key={c} value={c} className="capitalize">{c}</option>)}
          </select>
        </div>
      </div>

      {rooms.length > 0 && (
        <div className="flex flex-col gap-2">
          <label className="text-sm font-medium text-[var(--text-secondary)]">Room / Location</label>
          <select {...register('room_id')} className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60">
            <option value="">— no room assigned —</option>
            {rooms.map((r) => (
              <option key={r.id} value={r.id}>{r.name}{r.floor > 0 ? ` (Floor ${r.floor})` : ''}</option>
            ))}
          </select>
        </div>
      )}

      <div className="grid grid-cols-2 gap-3">
        <Input label="Purchase date" type="date" {...register('purchase_date')} />
        <Input label="Purchase price (€)" type="number" placeholder="e.g. 499" inputMode="decimal" {...register('purchase_price')} />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Input label="Current value (€)" type="number" placeholder="e.g. 350" inputMode="decimal" {...register('current_value')} />
        <Input label="Serial number" placeholder="Optional" {...register('serial_number')} />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Input label="Warranty expires" type="date" {...register('warranty_expires')} />
        <Input label="Warranty provider" placeholder="e.g. Samsung" {...register('warranty_provider')} />
      </div>

      <Input label="Manual URL" type="url" placeholder="https://…" {...register('manual_url')} />
      <Input label="Barcode / EAN" placeholder="Scan with M-SCAN™ or enter manually" {...register('barcode')} />

      <div className="flex flex-col gap-2">
        <label className="text-sm font-medium text-[var(--text-secondary)]">Tags</label>
        <input
          {...register('tags')}
          placeholder="appliance, kitchen, smart (comma-separated)"
          className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
        />
      </div>

      <div className="flex flex-col gap-2">
        <label className="text-sm font-medium text-[var(--text-secondary)]">Notes</label>
        <textarea {...register('notes')} rows={3} placeholder="Any additional details…" className="w-full rounded-xl border border-border glass-light px-3 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 resize-none" />
      </div>

      <div className="flex gap-3 pt-2">
        <Button type="button" variant="ghost" size="lg" onClick={() => router.back()}>Cancel</Button>
        <Button type="submit" size="lg" fullWidth loading={isSubmitting}>Add Item</Button>
      </div>
    </form>
  )
}
