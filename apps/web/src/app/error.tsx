'use client'

import { useEffect } from 'react'
import { RefreshCw } from 'lucide-react'

interface ErrorProps {
  error: Error & { digest?: string }
  reset: () => void
}

export default function ErrorPage({ error, reset }: ErrorProps) {
  useEffect(() => {
    console.error(error)
  }, [error])

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center gap-6 px-4 text-center">
      <div className="flex h-20 w-20 items-center justify-center rounded-3xl glass-standard">
        <span className="text-4xl">⚠️</span>
      </div>
      <div>
        <h2 className="text-2xl font-bold text-foreground">Something went wrong</h2>
        <p className="mt-2 text-sm text-muted-foreground max-w-[300px]">
          An unexpected error occurred. Please try again or contact support if the problem persists.
        </p>
      </div>
      <button
        onClick={reset}
        className="flex items-center gap-2 rounded-xl glass-standard px-5 py-2.5 text-sm font-medium text-foreground hover:glass-heavy transition-colors focus-ring"
      >
        <RefreshCw className="h-4 w-4" />
        Try Again
      </button>
    </div>
  )
}
