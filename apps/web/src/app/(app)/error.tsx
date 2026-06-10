'use client'

import { useEffect } from 'react'
import { AlertTriangle, RefreshCw } from 'lucide-react'
import { Button } from '@/components/ui/button'

export default function AppError({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  useEffect(() => {
    console.error(error)
  }, [error])

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-4 px-4 py-20 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-2xl glass-standard">
        <AlertTriangle className="h-7 w-7 text-destructive" />
      </div>
      <div>
        <p className="font-semibold text-foreground">Something went wrong</p>
        <p className="mt-1 text-sm text-muted-foreground max-w-[240px]">
          An unexpected error occurred. Try refreshing the page.
        </p>
      </div>
      <Button variant="primary" size="sm" onClick={reset}>
        <RefreshCw className="h-3.5 w-3.5" />
        Try again
      </Button>
    </div>
  )
}
