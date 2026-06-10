'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { Shield, KeyRound, LogOut, Trash2, ShieldCheck, ShieldOff } from 'lucide-react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { createClient } from '@/lib/supabase/client'

// ─── Password change ──────────────────────────────────────────────────────────

const pwSchema = z
  .object({
    newPassword: z.string().min(8, 'Password must be at least 8 characters'),
    confirmPassword: z.string(),
  })
  .refine((d) => d.newPassword === d.confirmPassword, {
    message: 'Passwords do not match',
    path: ['confirmPassword'],
  })

type PwValues = z.infer<typeof pwSchema>

// ─── MFA enrollment state ─────────────────────────────────────────────────────

type MfaState =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'enrolling'; factorId: string; qrSvg: string; secret: string }
  | { status: 'enrolled'; factorId: string }
  | { status: 'error'; message: string }

export function SecuritySettings({ userId: _userId }: { userId: string }) {
  const router = useRouter()
  const [isSigningOut, setIsSigningOut] = React.useState(false)
  const [pwSuccess, setPwSuccess] = React.useState(false)
  const [pwError, setPwError] = React.useState<string | null>(null)
  const [mfa, setMfa] = React.useState<MfaState>({ status: 'idle' })
  const [mfaCode, setMfaCode] = React.useState('')
  const [mfaVerifying, setMfaVerifying] = React.useState(false)
  const [mfaError, setMfaError] = React.useState<string | null>(null)
  const [showDeleteConfirm, setShowDeleteConfirm] = React.useState(false)
  const [deleteConfirmText, setDeleteConfirmText] = React.useState('')
  const [isDeleting, setIsDeleting] = React.useState(false)

  const { register, handleSubmit, reset, formState: { errors, isSubmitting } } = useForm<PwValues>({ resolver: zodResolver(pwSchema) })

  // Check existing MFA enrollment on mount
  React.useEffect(() => {
    async function checkMfa() {
      const supabase = createClient()
      const { data } = await supabase.auth.mfa.listFactors()
      const totp = data?.totp?.[0]
      if (totp?.status === 'verified') {
        setMfa({ status: 'enrolled', factorId: totp.id })
      }
    }
    checkMfa()
  }, [])

  async function onPasswordSubmit(values: PwValues) {
    setPwError(null); setPwSuccess(false)
    const supabase = createClient()
    const { error } = await supabase.auth.updateUser({ password: values.newPassword })
    if (error) { setPwError(error.message); return }
    setPwSuccess(true); reset()
  }

  async function handleSignOut() {
    setIsSigningOut(true)
    const supabase = createClient()
    await supabase.auth.signOut()
    router.push('/login')
  }

  async function handleEnrollMfa() {
    setMfa({ status: 'loading' }); setMfaError(null)
    const supabase = createClient()
    const { data, error } = await supabase.auth.mfa.enroll({
      factorType: 'totp',
      friendlyName: 'PRV HOUSE',
    })
    if (error || !data) {
      setMfa({ status: 'error', message: error?.message ?? 'Enrollment failed' })
      return
    }
    setMfa({ status: 'enrolling', factorId: data.id, qrSvg: data.totp.qr_code, secret: data.totp.secret })
  }

  async function handleVerifyMfa(e: React.FormEvent) {
    e.preventDefault()
    if (mfa.status !== 'enrolling') return
    if (mfaCode.length !== 6) { setMfaError('Enter the 6-digit code from your app'); return }
    setMfaVerifying(true); setMfaError(null)
    const supabase = createClient()
    const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId: mfa.factorId, code: mfaCode })
    setMfaVerifying(false)
    if (error) { setMfaError('Invalid code — please try again'); return }
    setMfa({ status: 'enrolled', factorId: mfa.factorId })
    setMfaCode('')
  }

  async function handleUnenrollMfa() {
    if (mfa.status !== 'enrolled') return
    if (!confirm('Disable two-factor authentication? Your account will be less secure.')) return
    const supabase = createClient()
    await supabase.auth.mfa.unenroll({ factorId: mfa.factorId })
    setMfa({ status: 'idle' })
  }

  async function handleDeleteAccount() {
    if (deleteConfirmText !== 'DELETE') return
    setIsDeleting(true)
    const res = await fetch('/api/account/delete', { method: 'DELETE' })
    if (!res.ok) {
      const { error } = await res.json()
      alert(error ?? 'Deletion failed. Please try again.')
      setIsDeleting(false)
      return
    }
    // Sign out locally then redirect
    const supabase = createClient()
    await supabase.auth.signOut()
    router.push('/register')
  }

  return (
    <div className="flex flex-col gap-6 max-w-lg">
      {/* Change Password */}
      <Card variant="default" padding="lg">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <KeyRound className="h-4 w-4" />Change Password
          </CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit(onPasswordSubmit)} className="flex flex-col gap-4">
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
            <Input label="New password" type="password" autoComplete="new-password" error={errors.newPassword?.message} {...register('newPassword')} />
            <Input label="Confirm new password" type="password" autoComplete="new-password" error={errors.confirmPassword?.message} {...register('confirmPassword')} />
            <div className="flex justify-end">
              <Button type="submit" variant="primary" size="md" loading={isSubmitting}>Update Password</Button>
            </div>
          </form>
        </CardContent>
      </Card>

      {/* 2FA */}
      <Card variant="default" padding="lg">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Shield className="h-4 w-4" />Two-Factor Authentication
          </CardTitle>
        </CardHeader>
        <CardContent>
          {mfa.status === 'idle' && (
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-foreground">Authenticator app</p>
                <p className="text-xs text-muted-foreground">Add an extra layer of security with TOTP</p>
              </div>
              <Button variant="primary" size="sm" onClick={handleEnrollMfa}>Enable 2FA</Button>
            </div>
          )}

          {mfa.status === 'loading' && (
            <p className="text-sm text-muted-foreground">Generating QR code…</p>
          )}

          {mfa.status === 'error' && (
            <div className="flex items-center justify-between">
              <p className="text-sm text-destructive">{mfa.message}</p>
              <Button variant="ghost" size="sm" onClick={() => setMfa({ status: 'idle' })}>Retry</Button>
            </div>
          )}

          {mfa.status === 'enrolling' && (
            <div className="flex flex-col gap-4">
              <p className="text-sm text-muted-foreground">
                Scan this QR code with <strong>Google Authenticator</strong>, <strong>Authy</strong>, or any TOTP app.
              </p>
              {/* QR code SVG from Supabase */}
              <div
                className="flex items-center justify-center rounded-xl bg-white p-4"
                // Safe: SVG comes directly from Supabase auth server
                dangerouslySetInnerHTML={{ __html: mfa.qrSvg }}
              />
              <div className="rounded-xl glass-light px-3 py-2">
                <p className="text-xs text-muted-foreground mb-1">Manual entry — secret key:</p>
                <p className="font-mono text-xs text-foreground break-all select-all">{mfa.secret}</p>
              </div>
              <form onSubmit={handleVerifyMfa} className="flex flex-col gap-3">
                {mfaError && <p className="text-sm text-destructive">{mfaError}</p>}
                <div className="flex flex-col gap-1.5">
                  <label className="text-sm font-medium text-[var(--text-secondary)]">Verification code</label>
                  <input
                    type="text" inputMode="numeric" pattern="\d{6}" maxLength={6}
                    placeholder="000000"
                    value={mfaCode}
                    onChange={(e) => setMfaCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                    className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 text-center font-mono text-lg tracking-widest text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                    autoFocus
                  />
                </div>
                <div className="flex gap-2">
                  <Button type="button" variant="ghost" size="sm" className="flex-1" onClick={() => { setMfa({ status: 'idle' }); setMfaCode('') }}>Cancel</Button>
                  <Button type="submit" variant="primary" size="sm" className="flex-1" loading={mfaVerifying}>Verify & Activate</Button>
                </div>
              </form>
            </div>
          )}

          {mfa.status === 'enrolled' && (
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <ShieldCheck className="h-4 w-4 text-success" />
                <div>
                  <p className="text-sm font-medium text-foreground">2FA is active</p>
                  <p className="text-xs text-muted-foreground">Your account is protected by an authenticator app</p>
                </div>
              </div>
              <Button variant="ghost" size="sm" onClick={handleUnenrollMfa} className="text-destructive hover:text-destructive">
                <ShieldOff className="h-3.5 w-3.5" />
                Disable
              </Button>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Sign out */}
      <Card variant="default" padding="lg">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <LogOut className="h-4 w-4" />Sessions
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-foreground">Sign out everywhere</p>
              <p className="text-xs text-muted-foreground">Sign out from all devices and sessions</p>
            </div>
            <Button variant="destructive" size="sm" loading={isSigningOut} onClick={handleSignOut}>Sign Out</Button>
          </div>
        </CardContent>
      </Card>

      {/* Delete account */}
      <Card variant="default" padding="lg">
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-destructive">
            <Trash2 className="h-4 w-4" />Delete Account
          </CardTitle>
        </CardHeader>
        <CardContent>
          {!showDeleteConfirm ? (
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-foreground">Permanently delete your account</p>
                <p className="text-xs text-muted-foreground">All your data will be erased and cannot be recovered</p>
              </div>
              <Button variant="destructive" size="sm" onClick={() => setShowDeleteConfirm(true)}>Delete</Button>
            </div>
          ) : (
            <div className="flex flex-col gap-3">
              <p className="text-sm text-destructive font-medium">This action is irreversible.</p>
              <p className="text-xs text-muted-foreground">
                All properties, inventory, maintenance records, documents, and family data linked to your account will be permanently deleted.
              </p>
              <div className="flex flex-col gap-1.5">
                <label className="text-xs text-muted-foreground">Type <strong className="text-foreground">DELETE</strong> to confirm</label>
                <input
                  type="text"
                  value={deleteConfirmText}
                  onChange={(e) => setDeleteConfirmText(e.target.value)}
                  className="h-10 rounded-xl border border-destructive/50 bg-destructive/5 px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-destructive/60"
                  placeholder="DELETE"
                  autoFocus
                />
              </div>
              <div className="flex gap-2">
                <Button variant="ghost" size="sm" className="flex-1" onClick={() => { setShowDeleteConfirm(false); setDeleteConfirmText('') }}>Cancel</Button>
                <Button
                  variant="destructive" size="sm" className="flex-1"
                  disabled={deleteConfirmText !== 'DELETE'}
                  loading={isDeleting}
                  onClick={handleDeleteAccount}
                >
                  Delete My Account
                </Button>
              </div>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
