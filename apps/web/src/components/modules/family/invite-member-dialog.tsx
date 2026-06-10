'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Copy, Check } from 'lucide-react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { createClient } from '@/lib/supabase/client'
import type { UserRole, PropertyInvitation } from '@/lib/supabase/types'
import { ROLE_LABELS } from '@/lib/supabase/types'

const schema = z.object({
  email: z.string().email('Please enter a valid email address'),
  role: z.enum(['partner', 'family_adult', 'family_teen', 'family_child', 'family_elderly', 'tenant', 'guest', 'service_provider']),
  message: z.string().max(500).optional(),
})

type FormValues = z.infer<typeof schema>

const INVITABLE_ROLES: UserRole[] = [
  'partner', 'family_adult', 'family_teen', 'family_child',
  'family_elderly', 'tenant', 'guest', 'service_provider',
]

interface InviteMemberDialogProps {
  open: boolean
  onClose: () => void
  propertyId: string
  propertyName: string
}

export function InviteMemberDialog({ open, onClose, propertyId, propertyName }: InviteMemberDialogProps) {
  const router = useRouter()
  const [serverError, setServerError] = React.useState<string | null>(null)
  const [inviteUrl, setInviteUrl] = React.useState<string | null>(null)
  const [copied, setCopied] = React.useState(false)

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { role: 'family_adult' },
  })

  async function onSubmit(values: FormValues) {
    setServerError(null)
    const supabase = createClient()
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return

    const expiresAt = new Date()
    expiresAt.setDate(expiresAt.getDate() + 7)

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: invitation, error } = await (supabase as any)
      .from('property_invitations')
      .insert({
        property_id: propertyId,
        invited_by: user.id,
        email: values.email,
        role: values.role,
        status: 'pending',
        message: values.message || null,
        expires_at: expiresAt.toISOString(),
        accepted_at: null,
      })
      .select('token')
      .single() as { data: Pick<PropertyInvitation, 'token'> | null; error: { message: string } | null }

    if (error || !invitation) {
      setServerError(error?.message ?? 'Failed to create invitation')
      return
    }

    const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? window.location.origin
    const url = `${siteUrl}/invite/${invitation.token}`
    setInviteUrl(url)

    // Fire-and-forget email via Edge Function (non-blocking)
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
    const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
    if (supabaseUrl && anonKey) {
      fetch(`${supabaseUrl}/functions/v1/send-invite-email`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: anonKey,
          Authorization: `Bearer ${anonKey}`,
        },
        body: JSON.stringify({
          to: values.email,
          inviterEmail: user.email ?? '',
          propertyName,
          role: values.role,
          inviteUrl: url,
        }),
      }).catch(() => {/* email is best-effort */})
    }

    reset()
    router.refresh()
  }

  async function copyLink() {
    if (!inviteUrl) return
    await navigator.clipboard.writeText(inviteUrl)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  function handleClose() {
    setInviteUrl(null)
    setServerError(null)
    setCopied(false)
    reset()
    onClose()
  }

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Invite a Member</DialogTitle>
          <DialogDescription>Send an invitation to join {propertyName}</DialogDescription>
        </DialogHeader>

        {inviteUrl ? (
          <div className="flex flex-col items-center gap-4 py-4 text-center">
            <div className="flex h-12 w-12 items-center justify-center rounded-full bg-success/20">
              <span className="text-2xl">✓</span>
            </div>
            <div>
              <p className="font-semibold text-foreground">Invitation created!</p>
              <p className="text-sm text-muted-foreground mt-1">
                An email is on its way. Share this link directly if needed:
              </p>
            </div>
            <div className="w-full flex items-center gap-2 rounded-xl border border-border glass-light px-3 py-2">
              <p className="flex-1 min-w-0 text-xs text-muted-foreground truncate">{inviteUrl}</p>
              <button
                type="button"
                onClick={copyLink}
                className="shrink-0 flex h-7 w-7 items-center justify-center rounded-lg glass-standard text-muted-foreground hover:text-foreground transition-colors"
                aria-label="Copy link"
              >
                {copied ? <Check className="h-3.5 w-3.5 text-success" /> : <Copy className="h-3.5 w-3.5" />}
              </button>
            </div>
            <Button onClick={handleClose} variant="ghost" size="sm">Done</Button>
          </div>
        ) : (
          <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4">
            {serverError && (
              <div className="rounded-xl border border-destructive/30 bg-destructive/10 px-4 py-3">
                <p className="text-sm text-destructive">{serverError}</p>
              </div>
            )}

            <Input
              label="Email address *"
              type="email"
              placeholder="member@example.com"
              error={errors.email?.message}
              {...register('email')}
            />

            <div className="flex flex-col gap-1.5">
              <label className="text-sm font-medium text-[var(--text-secondary)]">Role</label>
              <select
                {...register('role')}
                className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
              >
                {INVITABLE_ROLES.map((role) => (
                  <option key={role} value={role}>{ROLE_LABELS[role]}</option>
                ))}
              </select>
            </div>

            <Input
              label="Personal message"
              placeholder="Optional message to include in the invite"
              {...register('message')}
            />

            <DialogFooter>
              <Button type="button" variant="ghost" onClick={handleClose}>Cancel</Button>
              <Button type="submit" variant="primary" loading={isSubmitting}>Send Invitation</Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  )
}
