'use client'

import * as React from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Eye, EyeOff, Home, Check } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card } from '@/components/ui/card'
import { createClient } from '@/lib/supabase/client'
import { cn } from '@/lib/utils'

const registerSchema = z
  .object({
    fullName: z.string().min(2, 'Name must be at least 2 characters'),
    email: z.string().email('Please enter a valid email address'),
    password: z
      .string()
      .min(8, 'Password must be at least 8 characters')
      .regex(/[A-Z]/, 'Password must contain at least one uppercase letter')
      .regex(/[0-9]/, 'Password must contain at least one number'),
    confirmPassword: z.string(),
  })
  .refine((data) => data.password === data.confirmPassword, {
    message: 'Passwords do not match',
    path: ['confirmPassword'],
  })

type RegisterFormValues = z.infer<typeof registerSchema>

const PASSWORD_REQUIREMENTS = [
  { label: 'At least 8 characters', test: (p: string) => p.length >= 8 },
  { label: 'One uppercase letter', test: (p: string) => /[A-Z]/.test(p) },
  { label: 'One number', test: (p: string) => /[0-9]/.test(p) },
]

export function RegisterForm() {
  const router = useRouter()
  const [showPassword, setShowPassword] = React.useState(false)
  const [showConfirm, setShowConfirm] = React.useState(false)
  const [serverError, setServerError] = React.useState<string | null>(null)

  const {
    register,
    handleSubmit,
    watch,
    formState: { errors, isSubmitting },
  } = useForm<RegisterFormValues>({
    resolver: zodResolver(registerSchema),
    mode: 'onChange',
  })

  const password = watch('password', '')
  const passwordStrength = PASSWORD_REQUIREMENTS.filter((r) => r.test(password)).length

  async function onSubmit(values: RegisterFormValues) {
    setServerError(null)

    const supabase = createClient()
    const { error } = await supabase.auth.signUp({
      email: values.email,
      password: values.password,
      options: {
        data: {
          full_name: values.fullName,
        },
        emailRedirectTo: `${window.location.origin}/auth/callback`,
      },
    })

    if (error) {
      setServerError(
        error.message.includes('already registered')
          ? 'An account with this email already exists'
          : error.message
      )
      return
    }

    // Navigate to onboarding
    router.push('/onboarding')
    router.refresh()
  }

  return (
    <div className="w-full max-w-sm animate-slide-up">
      {/* Logo */}
      <div className="mb-8 flex flex-col items-center gap-3">
        <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary shadow-glow-home">
          <Home className="h-6 w-6 text-white" />
        </div>
        <div className="text-center">
          <h1 className="text-2xl font-bold tracking-tight text-gradient">
            Create your account
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Start managing your property smarter
          </p>
        </div>
      </div>

      {/* Form Card */}
      <Card variant="heavy" padding="lg">
        <form onSubmit={handleSubmit(onSubmit)} noValidate className="flex flex-col gap-4">
          {serverError && (
            <div
              className="rounded-lg border border-destructive/30 bg-destructive/10 px-4 py-3"
              role="alert"
            >
              <p className="text-sm text-destructive">{serverError}</p>
            </div>
          )}

          <Input
            label="Full name"
            type="text"
            autoComplete="name"
            placeholder="John Doe"
            error={errors.fullName?.message}
            {...register('fullName')}
          />

          <Input
            label="Email address"
            type="email"
            autoComplete="email"
            autoCapitalize="none"
            placeholder="you@example.com"
            error={errors.email?.message}
            {...register('email')}
          />

          <div className="flex flex-col gap-2">
            <Input
              label="Password"
              type={showPassword ? 'text' : 'password'}
              autoComplete="new-password"
              placeholder="••••••••"
              error={errors.password?.message}
              rightElement={
                <button
                  type="button"
                  onClick={() => setShowPassword((v) => !v)}
                  className="text-muted-foreground hover:text-foreground focus-ring rounded"
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                >
                  {showPassword ? (
                    <EyeOff className="h-4 w-4" />
                  ) : (
                    <Eye className="h-4 w-4" />
                  )}
                </button>
              }
              {...register('password')}
            />

            {/* Password strength */}
            {password.length > 0 && (
              <div className="flex flex-col gap-1.5">
                <div className="flex gap-1">
                  {[0, 1, 2].map((i) => (
                    <div
                      key={i}
                      className={cn(
                        'h-1 flex-1 rounded-full transition-colors duration-normal',
                        i < passwordStrength
                          ? passwordStrength === 1
                            ? 'bg-destructive'
                            : passwordStrength === 2
                              ? 'bg-[hsl(38,90%,50%)]'
                              : 'bg-[hsl(152,65%,48%)]'
                          : 'bg-border'
                      )}
                    />
                  ))}
                </div>
                <ul className="flex flex-col gap-1">
                  {PASSWORD_REQUIREMENTS.map((req) => (
                    <li
                      key={req.label}
                      className={cn(
                        'flex items-center gap-1.5 text-xs transition-colors duration-fast',
                        req.test(password)
                          ? 'text-[hsl(152,65%,48%)]'
                          : 'text-muted-foreground'
                      )}
                    >
                      <Check
                        className={cn(
                          'h-3 w-3 transition-opacity',
                          req.test(password) ? 'opacity-100' : 'opacity-30'
                        )}
                      />
                      {req.label}
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>

          <Input
            label="Confirm password"
            type={showConfirm ? 'text' : 'password'}
            autoComplete="new-password"
            placeholder="••••••••"
            error={errors.confirmPassword?.message}
            rightElement={
              <button
                type="button"
                onClick={() => setShowConfirm((v) => !v)}
                className="text-muted-foreground hover:text-foreground focus-ring rounded"
                aria-label={showConfirm ? 'Hide password' : 'Show password'}
              >
                {showConfirm ? (
                  <EyeOff className="h-4 w-4" />
                ) : (
                  <Eye className="h-4 w-4" />
                )}
              </button>
            }
            {...register('confirmPassword')}
          />

          <p className="text-xs text-muted-foreground">
            By creating an account, you agree to our{' '}
            <Link href="/terms" className="text-primary hover:underline focus-ring rounded">
              Terms of Service
            </Link>{' '}
            and{' '}
            <Link href="/privacy" className="text-primary hover:underline focus-ring rounded">
              Privacy Policy
            </Link>
          </p>

          <Button
            type="submit"
            fullWidth
            size="lg"
            loading={isSubmitting}
          >
            Create Account
          </Button>
        </form>
      </Card>

      <p className="mt-6 text-center text-sm text-muted-foreground">
        Already have an account?{' '}
        <Link
          href="/login"
          className="font-medium text-primary hover:text-primary/80 transition-colors duration-fast focus-ring rounded"
        >
          Sign in
        </Link>
      </p>
    </div>
  )
}
