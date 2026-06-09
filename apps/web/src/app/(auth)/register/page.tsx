import { type Metadata } from 'next'
import { RegisterForm } from '@/components/modules/auth/register-form'

export const metadata: Metadata = {
  title: 'Create Account',
}

export default function RegisterPage() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center px-4 py-12">
      <RegisterForm />
    </main>
  )
}
