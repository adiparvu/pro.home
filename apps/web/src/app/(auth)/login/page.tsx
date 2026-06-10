import { Suspense } from 'react'
import { type Metadata } from 'next'
import { LoginForm } from '@/components/modules/auth/login-form'

export const metadata: Metadata = {
  title: 'Sign In',
}

export default function LoginPage() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center px-4 py-12">
      <Suspense>
        <LoginForm />
      </Suspense>
    </main>
  )
}
