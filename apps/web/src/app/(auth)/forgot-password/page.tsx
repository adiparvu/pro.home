import { type Metadata } from 'next'
import { ForgotPasswordForm } from '@/components/modules/auth/forgot-password-form'

export const metadata: Metadata = { title: 'Reset Password' }

export default function ForgotPasswordPage() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center px-4 py-12">
      <ForgotPasswordForm />
    </main>
  )
}
