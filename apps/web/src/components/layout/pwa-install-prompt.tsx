'use client'

import * as React from 'react'
import { X } from 'lucide-react'

interface BeforeInstallPromptEvent extends Event {
  prompt(): Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

function isIOS() {
  if (typeof navigator === 'undefined') return false
  return /iPad|iPhone|iPod/.test(navigator.userAgent) && !(window as unknown as { MSStream?: unknown }).MSStream
}

function isDismissedRecently(): boolean {
  try {
    const raw = localStorage.getItem('pwa-install-dismissed')
    if (!raw) return false
    const ts = parseInt(raw, 10)
    const sevenDaysMs = 7 * 24 * 60 * 60 * 1000
    return Date.now() - ts < sevenDaysMs
  } catch {
    return false
  }
}

function markDismissed() {
  try {
    localStorage.setItem('pwa-install-dismissed', String(Date.now()))
  } catch {
    // ignore
  }
}

// Inline "P" mark SVG for PRV House
function PRVLogo() {
  return (
    <svg
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
    >
      <rect width="24" height="24" rx="6" fill="currentColor" />
      <text
        x="12"
        y="17"
        textAnchor="middle"
        fontFamily="system-ui, -apple-system, sans-serif"
        fontWeight="700"
        fontSize="14"
        fill="white"
      >
        P
      </text>
    </svg>
  )
}

export function PwaInstallPrompt() {
  const [prompt, setPrompt] = React.useState<BeforeInstallPromptEvent | null>(null)
  const [dismissed, setDismissed] = React.useState(false)
  const [installed, setInstalled] = React.useState(false)
  const [ios, setIos] = React.useState(false)
  const [showToast, setShowToast] = React.useState(false)

  React.useEffect(() => {
    // Don't show if already installed (standalone mode)
    if (window.matchMedia('(display-mode: standalone)').matches) {
      setInstalled(true)
      return
    }
    // Don't show if dismissed within 7 days
    if (isDismissedRecently()) {
      setDismissed(true)
      return
    }

    setIos(isIOS())

    function handler(e: Event) {
      e.preventDefault()
      setPrompt(e as BeforeInstallPromptEvent)
    }

    window.addEventListener('beforeinstallprompt', handler)
    return () => window.removeEventListener('beforeinstallprompt', handler)
  }, [])

  if (installed || dismissed) return null

  // For iOS, show manual instructions if no beforeinstallprompt (iOS doesn't support it)
  const showIOSInstructions = ios && !prompt
  if (!prompt && !showIOSInstructions) return null

  async function handleInstall() {
    if (!prompt) return
    await prompt.prompt()
    const { outcome } = await prompt.userChoice
    if (outcome === 'accepted') {
      setPrompt(null)
      setShowToast(true)
      setTimeout(() => setShowToast(false), 3000)
    }
    setDismissed(true)
  }

  function handleDismiss() {
    markDismissed()
    setDismissed(true)
  }

  return (
    <>
      {/* Install banner */}
      <div className="fixed bottom-[116px] md:bottom-4 left-4 right-4 md:left-auto md:right-4 md:w-80 z-40 animate-slide-up">
        <div className="flex items-start gap-3 rounded-2xl border border-border/40 bg-background/95 backdrop-blur-xl p-4 shadow-xl">
          {/* Logo */}
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary text-white">
            <PRVLogo />
          </div>

          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-foreground">PRV House</p>
            {showIOSInstructions ? (
              <>
                <p className="text-xs text-muted-foreground mt-0.5">
                  Tap <span className="font-medium">Share</span> → <span className="font-medium">Add to Home Screen</span> for the best experience.
                </p>
              </>
            ) : (
              <>
                <p className="text-xs text-muted-foreground mt-0.5">
                  Install PRV House for the best experience
                </p>
                <button
                  type="button"
                  onClick={handleInstall}
                  className="mt-2 rounded-lg bg-primary px-3 py-1.5 text-xs font-semibold text-white hover:bg-primary/80 transition-colors"
                >
                  Install
                </button>
              </>
            )}
          </div>

          <button
            type="button"
            onClick={handleDismiss}
            className="flex h-6 w-6 shrink-0 items-center justify-center rounded-lg text-muted-foreground hover:text-foreground transition-colors"
            aria-label="Dismiss install prompt"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>

      {/* Toast */}
      {showToast && (
        <div className="fixed bottom-[200px] md:bottom-20 left-1/2 -translate-x-1/2 z-50 rounded-xl bg-green-600 px-4 py-2.5 text-sm font-semibold text-white shadow-lg">
          PRV House installed!
        </div>
      )}
    </>
  )
}
