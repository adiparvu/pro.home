import Link from 'next/link'
import { Home } from 'lucide-react'

export default function NotFound() {
  return (
    <div className="flex min-h-dvh flex-col items-center justify-center gap-6 px-4 text-center">
      <div className="flex h-24 w-24 items-center justify-center rounded-3xl glass-standard">
        <span className="text-5xl">🏠</span>
      </div>
      <div>
        <h1 className="text-3xl font-bold text-foreground">Page not found</h1>
        <p className="mt-2 text-muted-foreground">
          This page doesn&apos;t exist or has been moved.
        </p>
      </div>
      <Link
        href="/"
        className="flex items-center gap-2 rounded-xl bg-primary px-5 py-2.5 text-sm font-semibold text-white shadow-glow-home transition-opacity hover:opacity-90 focus-ring"
      >
        <Home className="h-4 w-4" />
        Back to Dashboard
      </Link>
    </div>
  )
}
