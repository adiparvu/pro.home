'use client'

import * as React from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { Shield } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { createClient } from '@/lib/supabase/client'

export function MfaChallenge() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const redirectTo = searchParams.get('redirectTo') ?? '/'

  const [code, setCode] = React.useState('')
  const [error, setError] = React.useState<string | null>(null)
  const [loading, setLoading] = React.useState(false)

  async function handleVerify(e: React.FormEvent) {
    e.preventDefault()
    if (code.length !== 6) { setError('Please enter a 6-digit code'); return }
    setLoading(true)
    setError(null)

    const supabase = createClient()
    const { data: factors } = await supabase.auth.mfa.listFactors()
    const totp = factors?.totp?.[0]
    if (!totp) { setError('No authenticator found'); setLoading(false); return }

    const { data: challenge, error: challengeErr } = await supabase.auth.mfa.challenge({ factorId: totp.id })
    if (challengeErr || !challenge) { setError(challengeErr?.message ?? 'Challenge failed'); setLoading(false); return }

    const { error: verifyErr } = await supabase.auth.mfa.verify({
      factorId: totp.id,
      challengeId: challenge.id,
      code,
    })

    if (verifyErr) {
      setError('Invalid code — please try again')
      setLoading(false)
      return
    }

    router.push(redirectTo)
    router.refresh()
  }

  return (
    <div className="w-full max-w-sm animate-slide-up">
      <div className="mb-8 flex flex-col items-center gap-3">
        <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary shadow-glow-home">
          <Shield className="h-6 w-6 text-white" />
        </div>
        <div className="text-center">
          <h1 className="text-2xl font-bold tracking-tight text-gradient">Two-Factor Auth</h1>
          <p className="mt-1 text-sm text-muted-foreground">Enter the code from your authenticator app</p>
        </div>
      </div>

      <Card variant="heavy" padding="lg">
        <form onSubmit={handleVerify} className="flex flex-col gap-4">
          {error && (
            <div className="rounded-lg border border-destructive/30 bg-destructive/10 px-4 py-3" role="alert">
              <p className="text-sm text-destructive">{error}</p>
            </div>
          )}

          {/* 6-digit OTP input */}
          <div className="flex flex-col gap-1.5">
            <label className="text-sm font-medium text-[var(--text-secondary)]">Authentication code</label>
            <input
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              pattern="\d{6}"
              maxLength={6}
              placeholder="000000"
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
              className="h-14 w-full rounded-xl border border-border bg-glass-light px-4 text-center text-2xl font-mono tracking-[0.5em] text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
              autoFocus
            />
            <p className="text-xs text-muted-foreground text-center">Open your authenticator app to get your 6-digit code</p>
          </div>

          <Button type="submit" fullWidth size="lg" loading={loading}>
            Verify
          </Button>
        </form>
      </Card>
    </div>
  )
}
