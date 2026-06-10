'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Camera, User } from 'lucide-react'
import type { Profile } from '@/lib/supabase/types'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { createClient } from '@/lib/supabase/client'

const schema = z.object({
  full_name: z.string().min(1, 'Name is required').max(100),
  display_name: z.string().max(50).optional(),
  phone: z.string().max(20).optional(),
})

type FormValues = z.infer<typeof schema>

interface ProfileSettingsProps {
  profile: Profile | null
  userId: string
}

export function ProfileSettings({ profile, userId }: ProfileSettingsProps) {
  const router = useRouter()
  const [success, setSuccess] = React.useState(false)
  const [serverError, setServerError] = React.useState<string | null>(null)
  const [avatarUrl, setAvatarUrl] = React.useState<string | null>(profile?.avatar_url ?? null)
  const [uploadingAvatar, setUploadingAvatar] = React.useState(false)
  const avatarInputRef = React.useRef<HTMLInputElement>(null)

  async function handleAvatarUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    setUploadingAvatar(true)
    const supabase = createClient()
    const path = `avatars/${userId}/${Date.now()}-${file.name.replace(/[^a-z0-9.-]/gi, '_')}`
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error: storageError } = await (supabase as any).storage.from('documents').upload(path, file, { upsert: true, contentType: file.type })
    if (!storageError) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: urlData } = (supabase as any).storage.from('documents').getPublicUrl(path)
      const url = (urlData as { publicUrl: string }).publicUrl
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('profiles').update({ avatar_url: url }).eq('id', userId)
      setAvatarUrl(url)
    }
    setUploadingAvatar(false)
    if (avatarInputRef.current) avatarInputRef.current.value = ''
  }

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting, isDirty },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      full_name: profile?.full_name ?? '',
      display_name: profile?.display_name ?? '',
      phone: profile?.phone ?? '',
    },
  })

  async function onSubmit(values: FormValues) {
    setServerError(null)
    setSuccess(false)
    const supabase = createClient()

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error } = await (supabase as any)
      .from('profiles')
      .update({
        full_name: values.full_name,
        display_name: values.display_name || null,
        phone: values.phone || null,
      } satisfies Partial<Profile>)
      .eq('id', userId) as { error: { message: string } | null }

    if (error) {
      setServerError(error.message)
      return
    }

    setSuccess(true)
    router.refresh()
  }

  return (
    <div className="flex flex-col gap-6 max-w-lg">
      <Card variant="default" padding="lg">
        <CardHeader>
          <CardTitle>Personal Information</CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4">
            {/* Avatar */}
            <div className="flex items-center gap-4 pb-2">
              <div className="relative shrink-0">
                {avatarUrl ? (
                  <img
                    src={avatarUrl}
                    alt="Avatar"
                    className="h-16 w-16 rounded-full object-cover border border-border"
                  />
                ) : (
                  <div className="h-16 w-16 rounded-full glass-standard flex items-center justify-center">
                    <User className="h-7 w-7 text-muted-foreground" />
                  </div>
                )}
                <button
                  type="button"
                  onClick={() => avatarInputRef.current?.click()}
                  disabled={uploadingAvatar}
                  className="absolute -bottom-1 -right-1 h-7 w-7 rounded-full glass-heavy border border-border flex items-center justify-center hover:glass-standard transition-all focus-ring"
                  aria-label="Upload avatar"
                >
                  <Camera className="h-3 w-3 text-foreground" />
                </button>
              </div>
              <input
                ref={avatarInputRef}
                type="file"
                accept="image/jpeg,image/png,image/webp"
                onChange={handleAvatarUpload}
                className="hidden"
              />
              <div>
                <p className="text-sm font-medium text-foreground">{profile?.full_name ?? 'Your name'}</p>
                <p className="text-xs text-muted-foreground">{profile?.email}</p>
                {uploadingAvatar && (
                  <p className="text-xs text-primary animate-pulse mt-0.5">Uploading…</p>
                )}
              </div>
            </div>

            {serverError && (
              <div className="rounded-xl border border-destructive/30 bg-destructive/10 px-4 py-3" role="alert">
                <p className="text-sm text-destructive">{serverError}</p>
              </div>
            )}
            {success && (
              <div className="rounded-xl border border-success/30 bg-success/10 px-4 py-3" role="status">
                <p className="text-sm text-success">Profile updated successfully.</p>
              </div>
            )}

            <Input
              label="Full name *"
              error={errors.full_name?.message}
              {...register('full_name')}
            />
            <Input
              label="Display name"
              hint="Shown to other members instead of your full name"
              {...register('display_name')}
            />
            <Input
              label="Phone"
              type="tel"
              inputMode="tel"
              {...register('phone')}
            />

            <div className="flex justify-end pt-2">
              <Button
                type="submit"
                variant="primary"
                size="md"
                loading={isSubmitting}
                disabled={!isDirty}
              >
                Save Changes
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>

      <Card variant="default" padding="lg">
        <CardHeader>
          <CardTitle>Account</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-foreground">Email address</p>
                <p className="text-sm text-muted-foreground">{profile?.email}</p>
              </div>
            </div>
            <div className="border-t border-border/50" />
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-destructive">Delete Account</p>
                <p className="text-xs text-muted-foreground">
                  Permanently delete your account and all data
                </p>
              </div>
              <Button variant="destructive" size="sm">
                Delete
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
