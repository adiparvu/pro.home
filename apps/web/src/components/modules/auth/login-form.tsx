'use client'

import * as React from 'react'
import Link from 'next/link'
import { useRouter, useSearchParams } from 'next/navigation'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Eye, EyeOff, Home, Mail } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card } from '@/components/ui/card'
import { createClient } from '@/lib/supabase/client'
import { cn } from '@/lib/utils'

const loginSchema = z.object({
  email: z.string().email('Please enter a valid email address'),
  password: z.string().min(1, 'Password is required'),
})
const magicSchema = z.object({
  email: z.string().email('Please enter a valid email address'),
})

type LoginValues = z.infer<typeof loginSchema>
type MagicValues = z.infer<typeof magicSchema>

export function LoginForm() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const redirectTo = searchParams.get('redirectTo') ?? '/'

  const [mode, setMode] = React.useState<'password' | 'magic'>('password')
  const [showPassword, setShowPassword] = React.useState(false)
  const [serverError, setServerError] = React.useState<string | null>(null)
  const [magicSent, setMagicSent] = React.useState(false)

  const passwordForm = useForm<LoginValues>({ resolver: zodResolver(loginSchema) })
  const magicForm = useForm<MagicValues>({ resolver: zodResolver(magicSchema) })

  async function onPasswordSubmit(values: LoginValues) {
    setServerError(null)
    const supabase = createClient()
    const { error } = await supabase.auth.signInWithPassword({ email: values.email, password: values.password })
    if (error) {
      setServerError(error.message === 'Invalid login credentials' ? 'Invalid email or password' : error.message)
      return
    }
    // Check if MFA step-up is required
    const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
    if (aal?.nextLevel === 'aal2' && aal.currentLevel !== 'aal2') {
      router.push(`/mfa?redirectTo=${encodeURIComponent(redirectTo)}`)
      return
    }
    router.push(redirectTo)
    router.refresh()
  }

  async function onMagicSubmit(values: MagicValues) {
    setServerError(null)
    const supabase = createClient()
    const { error } = await supabase.auth.signInWithOtp({
      email: values.email,
      options: { emailRedirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent(redirectTo)}` },
    })
    if (error) { setServerError(error.message); return }
    setMagicSent(true)
  }

  return (
    <div className="w-full max-w-sm animate-slide-up">
      {/* Logo */}
      <div className="mb-8 flex flex-col items-center gap-3">
        <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary shadow-glow-home">
          <Home className="h-6 w-6 text-white" />
        </div>
        <div className="text-center">
          <h1 className="text-2xl font-bold tracking-tight text-gradient">Welcome back</h1>
          <p className="mt-1 text-sm text-muted-foreground">Your property intelligence awaits</p>
        </div>
      </div>

      <Card variant="heavy" padding="lg">
        {/* Mode tabs */}
        <div className="flex rounded-xl glass-light p-1 mb-4">
          {(['password', 'magic'] as const).map((m) => (
            <button
              key={m}
              type="button"
              onClick={() => { setMode(m); setServerError(null); setMagicSent(false) }}
              className={cn(
                'flex-1 rounded-lg py-1.5 text-sm font-medium transition-all',
                mode === m ? 'glass-standard text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground',
              )}
            >
              {m === 'password' ? 'Password' : 'Magic Link'}
            </button>
          ))}
        </div>

        {/* Error */}
        {serverError && (
          <div className="mb-4 rounded-lg border border-destructive/30 bg-destructive/10 px-4 py-3" role="alert">
            <p className="text-sm text-destructive">{serverError}</p>
          </div>
        )}

        {/* Password form */}
        {mode === 'password' && (
          <form onSubmit={passwordForm.handleSubmit(onPasswordSubmit)} noValidate className="flex flex-col gap-4">
            <Input
              label="Email address"
              type="email"
              autoComplete="email"
              autoCapitalize="none"
              placeholder="you@example.com"
              error={passwordForm.formState.errors.email?.message}
              {...passwordForm.register('email')}
            />
            <Input
              label="Password"
              type={showPassword ? 'text' : 'password'}
              autoComplete="current-password"
              placeholder="••••••••"
              error={passwordForm.formState.errors.password?.message}
              rightElement={
                <button
                  type="button"
                  onClick={() => setShowPassword((v) => !v)}
                  className="text-muted-foreground hover:text-foreground focus-ring rounded"
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                >
                  {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </button>
              }
              {...passwordForm.register('password')}
            />
            <div className="flex justify-end">
              <Link href="/forgot-password" className="text-sm text-muted-foreground hover:text-foreground transition-colors focus-ring rounded">
                Forgot password?
              </Link>
            </div>
            <Button type="submit" fullWidth size="lg" loading={passwordForm.formState.isSubmitting} className="mt-2">
              Sign In
            </Button>

            <div className="flex items-center gap-3">
              <div className="h-px flex-1 bg-border" />
              <span className="text-xs text-muted-foreground">or continue with</span>
              <div className="h-px flex-1 bg-border" />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <SocialButton provider="apple" redirectTo={redirectTo} />
              <SocialButton provider="google" redirectTo={redirectTo} />
            </div>
          </form>
        )}

        {/* Magic link form */}
        {mode === 'magic' && (
          magicSent ? (
            <div className="flex flex-col items-center gap-3 py-4 text-center">
              <div className="flex h-12 w-12 items-center justify-center rounded-full bg-primary/20">
                <Mail className="h-6 w-6 text-primary" />
              </div>
              <p className="font-semibold text-foreground">Check your email</p>
              <p className="text-sm text-muted-foreground">
                We sent a sign-in link to <strong>{magicForm.getValues('email')}</strong>.
                It expires in 1 hour.
              </p>
              <Button variant="ghost" size="sm" onClick={() => setMagicSent(false)}>
                Resend link
              </Button>
            </div>
          ) : (
            <form onSubmit={magicForm.handleSubmit(onMagicSubmit)} noValidate className="flex flex-col gap-4">
              <p className="text-sm text-muted-foreground">
                Enter your email and we&apos;ll send you a one-click sign-in link — no password needed.
              </p>
              <Input
                label="Email address"
                type="email"
                autoComplete="email"
                autoCapitalize="none"
                placeholder="you@example.com"
                error={magicForm.formState.errors.email?.message}
                {...magicForm.register('email')}
              />
              <Button type="submit" fullWidth size="lg" loading={magicForm.formState.isSubmitting}>
                Send Magic Link
              </Button>
            </form>
          )
        )}
      </Card>

      <p className="mt-6 text-center text-sm text-muted-foreground">
        Don&apos;t have an account?{' '}
        <Link href="/register" className="font-medium text-primary hover:text-primary/80 transition-colors focus-ring rounded">
          Sign up
        </Link>
      </p>
    </div>
  )
}

function SocialButton({ provider, redirectTo }: { provider: 'apple' | 'google'; redirectTo: string }) {
  const [loading, setLoading] = React.useState(false)
  async function handleClick() {
    setLoading(true)
    const supabase = createClient()
    await supabase.auth.signInWithOAuth({
      provider,
      options: { redirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent(redirectTo)}` },
    })
  }
  return (
    <Button
      type="button" variant="glass" size="md" fullWidth loading={loading} onClick={handleClick}
      className={cn('gap-2 text-sm', provider === 'apple' && 'hover:text-white', provider === 'google' && 'hover:text-white')}
    >
      {provider === 'apple' ? <AppleIcon className="h-4 w-4" /> : <GoogleIcon className="h-4 w-4" />}
      {provider === 'apple' ? 'Apple' : 'Google'}
    </Button>
  )
}

function AppleIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="currentColor">
      <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701" />
    </svg>
  )
}

function GoogleIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24">
      <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
      <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
      <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
      <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
    </svg>
  )
}
