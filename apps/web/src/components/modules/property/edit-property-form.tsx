'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Camera, Building2, Archive, ArchiveRestore } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { Input } from '@/components/ui/input'
import { toast } from '@/hooks/use-toast'
import { createClient } from '@/lib/supabase/client'
import type { HeatingType, Property } from '@/lib/supabase/types'

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
  num_floors: z.coerce.number().int().min(1).max(50).optional(),
  heating_type: z.enum(['gas', 'electric', 'heat_pump', 'oil', 'wood', 'district', 'solar', 'other']).optional(),
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

const HEATING_TYPES: { value: HeatingType; label: string }[] = [
  { value: 'gas', label: 'Gas' },
  { value: 'electric', label: 'Electric' },
  { value: 'heat_pump', label: 'Heat Pump' },
  { value: 'oil', label: 'Oil' },
  { value: 'wood', label: 'Wood / Pellet' },
  { value: 'district', label: 'District Heating' },
  { value: 'solar', label: 'Solar' },
  { value: 'other', label: 'Other' },
]

interface EditPropertyFormProps {
  property: Property
}

export function EditPropertyForm({ property }: EditPropertyFormProps) {
  const router = useRouter()
  const confirmDialog = useConfirm()
  const [serverError, setServerError] = React.useState<string | null>(null)
  const [photoUrl, setPhotoUrl] = React.useState<string | null>(property.photo_url)
  const [uploadingPhoto, setUploadingPhoto] = React.useState(false)
  const [archiving, setArchiving] = React.useState(false)
  const photoInputRef = React.useRef<HTMLInputElement>(null)

  async function handlePhotoUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    setUploadingPhoto(true)
    const supabase = createClient()
    const path = `property-photos/${property.id}/${Date.now()}-${file.name.replace(/[^a-z0-9.-]/gi, '_')}`
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error: storageError } = await (supabase as any).storage.from('documents').upload(path, file, { upsert: true, contentType: file.type })
    if (!storageError) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: urlData } = (supabase as any).storage.from('documents').getPublicUrl(path)
      const url = (urlData as { publicUrl: string }).publicUrl
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('properties').update({ photo_url: url }).eq('id', property.id)
      setPhotoUrl(url)
    }
    setUploadingPhoto(false)
    if (photoInputRef.current) photoInputRef.current.value = ''
  }

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      name: property.name,
      address_line1: property.address_line1,
      address_line2: property.address_line2 ?? undefined,
      city: property.city,
      state_province: property.state_province ?? undefined,
      postal_code: property.postal_code ?? undefined,
      country: property.country,
      property_type: property.property_type,
      size_sqm: property.size_sqm ?? undefined,
      year_built: property.year_built ?? undefined,
      num_rooms: property.num_rooms ?? undefined,
      num_bathrooms: property.num_bathrooms ?? undefined,
      num_floors: property.num_floors ?? undefined,
      heating_type: property.heating_type ?? undefined,
    },
  })

  async function onSubmit(values: FormValues) {
    setServerError(null)
    const supabase = createClient()

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error } = await (supabase as any).from('properties').update({
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
      num_floors: values.num_floors ?? null,
      heating_type: values.heating_type ?? null,
    }).eq('id', property.id)

    if (error) {
      setServerError((error as { message: string }).message ?? 'Failed to update property')
      return
    }

    router.push(`/property/${property.id}`)
    router.refresh()
  }

  async function handleArchiveToggle() {
    const newState = !property.is_active
    const ok = await confirmDialog({
      title: newState ? 'Restore this property?' : 'Archive this property?',
      description: newState
        ? 'It will appear in your active list.'
        : 'It will be hidden from your main list but all data is preserved.',
      confirmLabel: newState ? 'Restore' : 'Archive',
      destructive: true,
    })
    if (!ok) return
    setArchiving(true)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('properties').update({ is_active: newState }).eq('id', property.id)
    toast.success(newState ? 'Property restored' : 'Property archived')
    setArchiving(false)
    router.push('/property')
    router.refresh()
  }

  return (
    <>
    <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-5">
      {serverError && (
        <div className="rounded-xl border border-destructive/30 bg-destructive/10 px-4 py-3" role="alert">
          <p className="text-sm text-destructive">{serverError}</p>
        </div>
      )}

      {/* Property photo */}
      <div className="flex flex-col items-center gap-2 py-2">
        <div className="relative">
          {photoUrl ? (
            <img
              src={photoUrl}
              alt="Property"
              className="h-24 w-24 rounded-2xl object-cover border border-border"
            />
          ) : (
            <div className="h-24 w-24 rounded-2xl glass-standard flex items-center justify-center">
              <Building2 className="h-10 w-10 text-muted-foreground" />
            </div>
          )}
          <button
            type="button"
            onClick={() => photoInputRef.current?.click()}
            disabled={uploadingPhoto}
            className="absolute -bottom-2 -right-2 h-8 w-8 rounded-full glass-heavy border border-border flex items-center justify-center hover:glass-standard transition-all focus-ring"
            aria-label="Upload property photo"
          >
            <Camera className="h-3.5 w-3.5 text-foreground" />
          </button>
        </div>
        <input
          ref={photoInputRef}
          type="file"
          accept="image/jpeg,image/png,image/webp"
          onChange={handlePhotoUpload}
          className="hidden"
        />
        {uploadingPhoto && (
          <p className="text-xs text-muted-foreground animate-pulse">Uploading…</p>
        )}
        <p className="text-xs text-muted-foreground">Tap the camera icon to change photo</p>
      </div>

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
        <Input label="Postal code" placeholder="e.g. 400001" {...register('postal_code')} />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Input label="State / Province" placeholder="e.g. Cluj" {...register('state_province')} />
        <Input
          label="Country *"
          placeholder="e.g. RO"
          error={errors.country?.message}
          {...register('country')}
        />
      </div>

      <div className="flex flex-col gap-2">
        <label className="text-sm font-medium text-[var(--text-secondary)]">Property type</label>
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
        <Input label="Size (m²)" type="number" placeholder="e.g. 120" inputMode="numeric" {...register('size_sqm')} />
        <Input label="Year built" type="number" placeholder="e.g. 2005" inputMode="numeric" {...register('year_built')} />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Input label="Rooms" type="number" placeholder="e.g. 3" inputMode="numeric" {...register('num_rooms')} />
        <Input label="Bathrooms" type="number" placeholder="e.g. 2" inputMode="numeric" {...register('num_bathrooms')} />
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Input label="Floors" type="number" placeholder="e.g. 2" inputMode="numeric" {...register('num_floors')} />
        <div className="flex flex-col gap-2">
          <label className="text-sm font-medium text-[var(--text-secondary)]">Heating</label>
          <select
            {...register('heating_type')}
            className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
          >
            <option value="">— select —</option>
            {HEATING_TYPES.map((t) => (
              <option key={t.value} value={t.value}>{t.label}</option>
            ))}
          </select>
        </div>
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

    {/* Archive / Restore */}
    <div className="mt-6 rounded-2xl border border-destructive/20 bg-destructive/5 p-4">
      <p className="text-sm font-medium text-destructive mb-1">
        {property.is_active ? 'Archive Property' : 'Restore Property'}
      </p>
      <p className="text-xs text-muted-foreground mb-3">
        {property.is_active
          ? 'Hide this property from your main list. All data is preserved and it can be restored at any time.'
          : 'Move this property back to your active list.'}
      </p>
      <Button
        type="button"
        variant={property.is_active ? 'destructive' : 'ghost'}
        size="sm"
        loading={archiving}
        onClick={handleArchiveToggle}
      >
        {property.is_active
          ? <><Archive className="h-3.5 w-3.5" />Archive</>
          : <><ArchiveRestore className="h-3.5 w-3.5" />Restore</>}
      </Button>
    </div>
    </>
  )
}
