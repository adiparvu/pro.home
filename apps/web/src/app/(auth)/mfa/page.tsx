import { Suspense } from 'react'
import { type Metadata } from 'next'
import { MfaChallenge } from '@/components/modules/auth/mfa-challenge'

export const metadata: Metadata = { title: 'Two-Factor Authentication' }

export default function MfaPage() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center px-4 py-12">
      <Suspense>
        <MfaChallenge />
      </Suspense>
    </main>
  )
}
