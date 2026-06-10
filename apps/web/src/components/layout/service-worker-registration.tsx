'use client'

import * as React from 'react'

export function ServiceWorkerRegistration() {
  React.useEffect(() => {
    if ('serviceWorker' in navigator && process.env.NODE_ENV === 'production') {
      navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(() => {
        // Registration is best-effort — never break the app
      })
    }
  }, [])
  return null
}
