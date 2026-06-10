import { Providers } from '@/components/layout/providers'

export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <Providers>
      <div className="relative min-h-dvh overflow-hidden">
        {/* Living Property Background */}
        <div
          className="absolute inset-0 lpbe-bg"
          aria-hidden="true"
        />
        {/* Glass overlay for readability */}
        <div
          className="absolute inset-0 bg-black/20"
          aria-hidden="true"
        />
        {/* Content */}
        <div className="relative z-10 flex min-h-dvh flex-col">
          {children}
        </div>
      </div>
    </Providers>
  )
}
