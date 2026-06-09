'use client'

import * as React from 'react'
import Link from 'next/link'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { ArrowLeft, Home, MailCheck } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card } from '@/components/ui/card'
import { createClient } from '@/lib/supabase/client'

const forgotSchema = z.object({
  email: z.string().email('Please enter a valid email address'),
})

type ForgotFormValues = z.infer<typeof forgotSchema>

export function ForgotPasswordForm() {
  const [sent, setSent] = React.useState(false)
  const [sentEmail, setSentEmail] = React.useState('')

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<ForgotFormValues>({
    resolver: zodResolver(forgotSchema),
  })

  async function onSubmit(values: ForgotFormValues) {
    const supabase = createClient()
    await supabase.auth.resetPasswordForEmail(values.email, {
      redirectTo: `${window.location.origin}/auth/callback?next=/reset-password`,
    })
    // Always show success (don't reveal if email exists)
    setSentEmail(values.email)
    setSent(true)
  }

  return (
    <div className="w-full max-w-sm animate-slide-up">
      <div className="mb-8 flex flex-col items-center gap-3">
        <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary shadow-glow-home">
          {sent ? <MailCheck className="h-6 w-6 text-white" /> : <Home className="h-6 w-6 text-white" />}
        </div>
        <div className="text-center">
          <h1 className="text-2xl font-bold tracking-tight text-gradient">
            {sent ? 'Check your email' : 'Reset password'}
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            {sent
              ? `We sent a link to ${sentEmail}`
              : "Enter your email and we'll send a reset link"}
          </p>
        </div>
      </div>

      {!sent ? (
        <Card variant="heavy" padding="lg">
          <form onSubmit={handleSubmit(onSubmit)} noValidate className="flex flex-col gap-4">
            <Input
              label="Email address"
              type="email"
              autoComplete="email"
              placeholder="you@example.com"
              error={errors.email?.message}
              {...register('email')}
            />

            <Button type="submit" fullWidth size="lg" loading={isSubmitting}>
              Send Reset Link
            </Button>
          </form>
        </Card>
      ) : (
        <Card variant="heavy" padding="lg" className="text-center">
          <p className="text-sm text-muted-foreground">
            If an account exists for that email, you&apos;ll receive a password reset link shortly.
            Check your spam folder if you don&apos;t see it.
          </p>
        </Card>
      )}

      <div className="mt-6 text-center">
        <Link
          href="/login"
          className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors focus-ring rounded"
        >
          <ArrowLeft className="h-3.5 w-3.5" />
          Back to Sign In
        </Link>
      </div>
    </div>
  )
}
