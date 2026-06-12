'use client'

export default function GlobalError({
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  return (
    <html lang="en">
      <body
        style={{
          minHeight: '100dvh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: '#0D0D0D',
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
          <button
            onClick={reset}
            style={{
              display: 'inline-block',
              background: '#fff',
              color: '#000',
              borderRadius: 12,
              padding: '10px 20px',
              fontSize: 14,
              fontWeight: 600,
              border: 'none',
              cursor: 'pointer',
            }}
          >
            Try again
          </button>
        </div>
      </body>
    </html>
  )
}
