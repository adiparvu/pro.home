'use client'

import * as React from 'react'
import { BellRing, X } from 'lucide-react'
import { toast } from '@/hooks/use-toast'

const DISMISS_KEY = 'prv-push-banner-dismissed'

function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/')
  const rawData = atob(base64)
  return Uint8Array.from([...rawData].map((c) => c.charCodeAt(0)))
}

/**
 * Prompts the user to enable Web Push. Hidden when unsupported, already
 * subscribed, permission denied, or previously dismissed.
 */
export function PushBanner() {
  const [visible, setVisible] = React.useState(false)
  const [busy, setBusy] = React.useState(false)

  React.useEffect(() => {
    async function check() {
      if (
        typeof window === 'undefined' ||
        !('serviceWorker' in navigator) ||
        !('PushManager' in window) ||
        !process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY ||
        Notification.permission === 'denied' ||
        localStorage.getItem(DISMISS_KEY)
      ) {
        return
      }
      const registration = await navigator.serviceWorker.getRegistration()
      if (!registration) return // SW only registers in production
      const existing = await registration.pushManager.getSubscription()
      if (!existing) setVisible(true)
    }
    check().catch(() => {})
  }, [])

  async function enable() {
    setBusy(true)
    try {
      const permission = await Notification.requestPermission()
      if (permission !== 'granted') {
        setVisible(false)
        return
      }
      const registration = await navigator.serviceWorker.ready
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY!),
      })
      const res = await fetch('/api/push/subscribe', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(subscription.toJSON()),
      })
      if (!res.ok) throw new Error('subscribe failed')
      setVisible(false)
      toast.success('Push notifications enabled')
    } catch {
      toast.error('Could not enable push notifications')
    } finally {
      setBusy(false)
    }
  }

  function dismiss() {
    localStorage.setItem(DISMISS_KEY, '1')
    setVisible(false)
  }

  if (!visible) return null

  return (
    <div className="mx-4 mt-3 flex items-center gap-3 rounded-2xl glass-standard p-3 md:mx-6">
      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary/15">
        <BellRing className="h-5 w-5 text-primary" />
      </div>
      <div className="min-w-0 flex-1">
        <p className="text-sm font-semibold text-foreground">Get alerts on this device</p>
        <p className="text-xs text-muted-foreground">
          Overdue tasks, recalls and expiring documents — even when the app is closed.
        </p>
      </div>
      <button
        type="button"
        onClick={enable}
        disabled={busy}
        className="shrink-0 rounded-xl bg-primary px-3.5 py-2 text-xs font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-60 focus-ring"
      >
        {busy ? 'Enabling…' : 'Enable'}
      </button>
      <button
        type="button"
        onClick={dismiss}
        aria-label="Dismiss"
        className="shrink-0 rounded-lg p-1.5 text-muted-foreground transition-colors hover:text-foreground focus-ring"
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  )
}
