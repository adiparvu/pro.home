'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { Shield, KeyRound, LogOut } from 'lucide-react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { createClient } from '@/lib/supabase/client'

const schema = z
  .object({
    newPassword: z.string().min(8, 'Password must be at least 8 characters'),
    confirmPassword: z.string(),
  })
  .refine((d) => d.newPassword === d.confirmPassword, {
    message: 'Passwords do not match',
    path: ['confirmPassword'],
  })

type FormValues = z.infer<typeof schema>

export function SecuritySettings({ userId: _userId }: { userId: string }) {
  const router = useRouter()
  const [isSigningOut, setIsSigningOut] = React.useState(false)
  const [pwSuccess, setPwSuccess] = React.useState(false)
  const [pwError, setPwError] = React.useState<string | null>(null)

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({ resolver: zodResolver(schema) })

  async function onSubmit(values: FormValues) {
    setPwError(null)
    setPwSuccess(false)
    const supabase = createClient()
    const { error } = await supabase.auth.updateUser({ password: values.newPassword })
    if (error) {
      setPwError(error.message)
      return
    }
    setPwSuccess(true)
    reset()
  }

  async function handleSignOut() {
    setIsSigningOut(true)
    const supabase = createClient()
    await supabase.auth.signOut()
    router.push('/login')
  }

  return (
    <div className="flex flex-col gap-6 max-w-lg">
      {/* Change Password */}
      <Card variant="default" padding="lg">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <KeyRound className="h-4 w-4" />
            Change Password
          </CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4">
            {pwError && (
              <div className="rounded-xl border border-destructive/30 bg-destructive/10 px-4 py-3">
                <p className="text-sm text-destructive">{pwError}</p>
              </div>
            )}
            {pwSuccess && (
              <div className="rounded-xl border border-success/30 bg-success/10 px-4 py-3">
                <p className="text-sm text-success">Password updated successfully.</p>
              </div>
            )}
            <Input
              label="New password"
              type="password"
              autoComplete="new-password"
              error={errors.newPassword?.message}
              {...register('newPassword')}
            />
            <Input
              label="Confirm new password"
              type="password"
              autoComplete="new-password"
              error={errors.confirmPassword?.message}
              {...register('confirmPassword')}
            />
            <div className="flex justify-end">
              <Button type="submit" variant="primary" size="md" loading={isSubmitting}>
                Update Password
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>

      {/* 2FA placeholder */}
      <Card variant="default" padding="lg">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Shield className="h-4 w-4" />
            Two-Factor Authentication
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-foreground">Authenticator app</p>
              <p className="text-xs text-muted-foreground">Add an extra layer of security</p>
            </div>
            <Button variant="outline" size="sm" disabled>
              Coming Soon
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Sign out */}
      <Card variant="default" padding="lg">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <LogOut className="h-4 w-4" />
            Sessions
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-foreground">Sign out everywhere</p>
              <p className="text-xs text-muted-foreground">
                Sign out from all devices and sessions
              </p>
            </div>
            <Button variant="destructive" size="sm" loading={isSigningOut} onClick={handleSignOut}>
              Sign Out
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
