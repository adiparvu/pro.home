'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
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
import type { UserRole } from '@/lib/supabase/types'
import { ROLE_LABELS } from '@/lib/supabase/types'

const schema = z.object({
  email: z.string().email('Please enter a valid email address'),
  role: z.enum(['partner', 'family_adult', 'family_teen', 'family_child', 'family_elderly', 'tenant', 'guest', 'service_provider']),
  message: z.string().max(500).optional(),
})

type FormValues = z.infer<typeof schema>

const INVITABLE_ROLES: UserRole[] = [
  'partner',
  'family_adult',
  'family_teen',
  'family_child',
  'family_elderly',
  'tenant',
  'guest',
  'service_provider',
]

interface InviteMemberDialogProps {
  open: boolean
  onClose: () => void
  propertyId: string
}

export function InviteMemberDialog({ open, onClose, propertyId }: InviteMemberDialogProps) {
  const router = useRouter()
  const [serverError, setServerError] = React.useState<string | null>(null)
  const [success, setSuccess] = React.useState(false)

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

    const expiresAt = new Date()
    expiresAt.setDate(expiresAt.getDate() + 7)

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error } = await (supabase as any).from('property_invitations').insert({
      property_id: propertyId,
      invited_by: (await supabase.auth.getUser()).data.user!.id,
      email: values.email,
      role: values.role,
      status: 'pending',
      message: values.message || null,
      expires_at: expiresAt.toISOString(),
      accepted_at: null,
    }) as { error: { message: string } | null }

    if (error) {
      setServerError(error.message)
      return
    }

    setSuccess(true)
    reset()
    router.refresh()
  }

  function handleClose() {
    setSuccess(false)
    setServerError(null)
    reset()
    onClose()
  }

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Invite a Member</DialogTitle>
          <DialogDescription>
            Send an invitation to join your property
          </DialogDescription>
        </DialogHeader>

        {success ? (
          <div className="flex flex-col items-center gap-3 py-6 text-center">
            <div className="flex h-12 w-12 items-center justify-center rounded-full bg-success/20">
              <span className="text-2xl">✓</span>
            </div>
            <p className="font-semibold text-foreground">Invitation sent!</p>
            <p className="text-sm text-muted-foreground">
              They'll receive an email with instructions to join.
            </p>
            <Button onClick={handleClose} variant="ghost" size="sm">
              Close
            </Button>
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
              <label className="text-sm font-medium text-[var(--text-secondary)]">
                Role
              </label>
              <select
                {...register('role')}
                className="h-11 w-full rounded-xl border border-border bg-glass-light px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
              >
                {INVITABLE_ROLES.map((role) => (
                  <option key={role} value={role}>
                    {ROLE_LABELS[role]}
                  </option>
                ))}
              </select>
            </div>

            <Input
              label="Personal message"
              placeholder="Optional message to include in the invite"
              {...register('message')}
            />

            <DialogFooter>
              <Button type="button" variant="ghost" onClick={handleClose}>
                Cancel
              </Button>
              <Button type="submit" variant="primary" loading={isSubmitting}>
                Send Invitation
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  )
}
