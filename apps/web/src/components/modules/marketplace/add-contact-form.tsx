'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Star, X } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'

const schema = z.object({
  name: z.string().min(1, 'Name is required').max(120),
  category: z.string().min(1, 'Category is required'),
  description: z.string().max(500).optional(),
  phone: z.string().max(40).optional(),
  email: z.string().email('Invalid email').max(120).optional().or(z.literal('')),
  website: z.string().url('Invalid URL').max(200).optional().or(z.literal('')),
  notes: z.string().max(1000).optional(),
  rating: z.number().int().min(1).max(5).nullable(),
})

type FormValues = z.infer<typeof schema>

const CATEGORY_OPTIONS = [
  'Plumbing', 'Electrical', 'HVAC', 'Cleaning', 'Painting',
  'Security', 'Landscaping', 'General Handyman', 'Roofing',
  'Windows & Doors', 'Flooring', 'Pest Control', 'Other',
]

interface AddContactFormProps {
  propertyId: string
  userId: string
}

export function AddContactForm({ propertyId, userId }: AddContactFormProps) {
  const router = useRouter()
  const [tagInput, setTagInput] = React.useState('')
  const [tags, setTags] = React.useState<string[]>([])
  const [saving, setSaving] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)

  const { register, handleSubmit, setValue, watch, formState: { errors } } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { rating: null },
  })

  const rating = watch('rating')

  function addTag(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'Enter' || e.key === ',') {
      e.preventDefault()
      const val = tagInput.trim()
      if (val && !tags.includes(val) && tags.length < 8) {
        setTags((prev) => [...prev, val])
      }
      setTagInput('')
    }
  }

  function removeTag(tag: string) {
    setTags((prev) => prev.filter((t) => t !== tag))
  }

  async function onSubmit(data: FormValues) {
    setSaving(true)
    setError(null)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { error: insertError } = await (supabase as any).from('marketplace_contacts').insert({
        property_id: propertyId,
        created_by: userId,
        name: data.name,
        category: data.category,
        description: data.description || null,
        phone: data.phone || null,
        email: data.email || null,
        website: data.website || null,
        notes: data.notes || null,
        rating: data.rating,
        tags,
      })
      if (insertError) throw insertError
      router.push('/marketplace')
      router.refresh()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save contact')
    } finally {
      setSaving(false)
    }
  }

  const inputCls = 'h-11 w-full rounded-xl border border-border glass-light px-4 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60'
  const labelCls = 'text-xs text-muted-foreground'
  const errorCls = 'mt-1 text-xs text-destructive'

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 max-w-xl mx-auto">
      {error && (
        <div className="rounded-xl border border-destructive/30 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          {error}
        </div>
      )}

      {/* Name */}
      <div className="flex flex-col gap-1.5">
        <label className={labelCls}>Name *</label>
        <input {...register('name')} placeholder="e.g. AquaFix Plumbing" className={inputCls} />
        {errors.name && <p className={errorCls}>{errors.name.message}</p>}
      </div>

      {/* Category */}
      <div className="flex flex-col gap-1.5">
        <label className={labelCls}>Category *</label>
        <select
          {...register('category')}
          className="h-11 w-full rounded-xl border border-border glass-light px-4 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 bg-transparent"
        >
          <option value="">Select category…</option>
          {CATEGORY_OPTIONS.map((c) => (
            <option key={c} value={c}>{c}</option>
          ))}
        </select>
        {errors.category && <p className={errorCls}>{errors.category.message}</p>}
      </div>

      {/* Description */}
      <div className="flex flex-col gap-1.5">
        <label className={labelCls}>Description</label>
        <textarea
          {...register('description')}
          rows={3}
          placeholder="What do they do?"
          className="w-full rounded-xl border border-border glass-light px-4 py-2.5 text-sm text-foreground placeholder:text-muted-foreground resize-none focus:outline-none focus:ring-2 focus:ring-primary/60"
        />
      </div>

      {/* Phone + Email */}
      <div className="grid grid-cols-2 gap-3">
        <div className="flex flex-col gap-1.5">
          <label className={labelCls}>Phone</label>
          <input {...register('phone')} placeholder="+351 91 234 5678" className={inputCls} />
        </div>
        <div className="flex flex-col gap-1.5">
          <label className={labelCls}>Email</label>
          <input {...register('email')} type="email" placeholder="contact@example.com" className={inputCls} />
          {errors.email && <p className={errorCls}>{errors.email.message}</p>}
        </div>
      </div>

      {/* Website */}
      <div className="flex flex-col gap-1.5">
        <label className={labelCls}>Website</label>
        <input {...register('website')} type="url" placeholder="https://example.com" className={inputCls} />
        {errors.website && <p className={errorCls}>{errors.website.message}</p>}
      </div>

      {/* Rating */}
      <div className="flex flex-col gap-1.5">
        <label className={labelCls}>Your rating</label>
        <div className="flex gap-1">
          {[1, 2, 3, 4, 5].map((n) => (
            <button
              key={n}
              type="button"
              onClick={() => setValue('rating', rating === n ? null : n)}
              className="p-1"
            >
              <Star
                className={cn('h-6 w-6 transition-colors', n <= (rating ?? 0) ? 'fill-[hsl(45,75%,52%)] text-[hsl(45,75%,52%)]' : 'text-muted-foreground')}
              />
            </button>
          ))}
        </div>
      </div>

      {/* Tags */}
      <div className="flex flex-col gap-1.5">
        <label className={labelCls}>Tags</label>
        <input
          value={tagInput}
          onChange={(e) => setTagInput(e.target.value)}
          onKeyDown={addTag}
          placeholder="Type a tag and press Enter"
          className={inputCls}
        />
        {tags.length > 0 && (
          <div className="flex flex-wrap gap-1.5 mt-1">
            {tags.map((tag) => (
              <span key={tag} className="flex items-center gap-1 rounded-full glass-light px-2.5 py-1 text-xs text-foreground">
                {tag}
                <button type="button" onClick={() => removeTag(tag)} className="text-muted-foreground hover:text-foreground">
                  <X className="h-3 w-3" />
                </button>
              </span>
            ))}
          </div>
        )}
      </div>

      {/* Notes */}
      <div className="flex flex-col gap-1.5">
        <label className={labelCls}>Notes</label>
        <textarea
          {...register('notes')}
          rows={3}
          placeholder="Private notes about this contact…"
          className="w-full rounded-xl border border-border glass-light px-4 py-2.5 text-sm text-foreground placeholder:text-muted-foreground resize-none focus:outline-none focus:ring-2 focus:ring-primary/60"
        />
      </div>

      <Button type="submit" variant="primary" loading={saving} className="mt-2">
        Save contact
      </Button>
    </form>
  )
}
