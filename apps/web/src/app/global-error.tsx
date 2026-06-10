'use client'

import * as React from 'react'
import * as Sentry from '@sentry/nextjs'

/**
 * Root-level error boundary: catches React rendering errors in the root
 * layout itself and reports them to Sentry. Must render its own <html>.
 */
export default function GlobalError({
  error,
}: {
  error: Error & { digest?: string }
}) {
  React.useEffect(() => {
    Sentry.captureException(error)
  }, [error])

  return (
    <html lang="en">
      <body
        style={{
          minHeight: '100dvh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: '#0D1420',
          color: '#fff',
          fontFamily: 'system-ui, sans-serif',
          textAlign: 'center',
          padding: '24px',
        }}
      >
        <div>
          <p style={{ fontSize: 40, marginBottom: 12 }}>🏠</p>
          <h1 style={{ fontSize: 20, fontWeight: 700, marginBottom: 8 }}>
            Something went wrong
          </h1>
          <p style={{ opacity: 0.7, fontSize: 14, marginBottom: 20 }}>
            An unexpected error occurred. Reloading usually fixes it.
          </p>
          <a
            href="/"
            style={{
              display: 'inline-block',
              background: '#2E8FEC',
              color: '#fff',
              borderRadius: 12,
              padding: '10px 20px',
              fontSize: 14,
              fontWeight: 600,
              textDecoration: 'none',
            }}
          >
            Reload PRV HOUSE
          </a>
        </div>
      </body>
    </html>
  )
}
