'use client'

import * as React from 'react'
import { Download, X, Home } from 'lucide-react'

interface BeforeInstallPromptEvent extends Event {
  prompt(): Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

export function PwaInstallPrompt() {
  const [prompt, setPrompt] = React.useState<BeforeInstallPromptEvent | null>(null)
  const [dismissed, setDismissed] = React.useState(false)

  React.useEffect(() => {
    // Don't show if already installed
    if (window.matchMedia('(display-mode: standalone)').matches) return
    // Don't show if dismissed in this session
    if (sessionStorage.getItem('pwa-prompt-dismissed')) return

    function handler(e: Event) {
      e.preventDefault()
      setPrompt(e as BeforeInstallPromptEvent)
    }

    window.addEventListener('beforeinstallprompt', handler)
    return () => window.removeEventListener('beforeinstallprompt', handler)
  }, [])

  if (!prompt || dismissed) return null

  async function handleInstall() {
    if (!prompt) return
    await prompt.prompt()
    const { outcome } = await prompt.userChoice
    if (outcome === 'accepted') setPrompt(null)
    setDismissed(true)
  }

  function handleDismiss() {
    sessionStorage.setItem('pwa-prompt-dismissed', '1')
    setDismissed(true)
  }

  return (
    <div className="fixed bottom-[100px] left-4 right-4 z-[45] md:left-auto md:right-6 md:bottom-6 md:w-80 animate-slide-up">
      <div className="flex items-start gap-3 rounded-2xl glass-heavy border border-border/50 p-4 shadow-xl">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary shadow-glow-home">
          <Home className="h-5 w-5 text-white" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold text-foreground">Install PRV HOUSE</p>
          <p className="text-xs text-muted-foreground mt-0.5">Add to home screen for the full native experience</p>
          <button
            type="button"
            onClick={handleInstall}
            className="mt-2 flex items-center gap-1.5 rounded-lg bg-primary px-3 py-1.5 text-xs font-semibold text-white hover:bg-primary/80 transition-colors"
          >
            <Download className="h-3.5 w-3.5" />
            Install app
          </button>
        </div>
        <button
          type="button"
          onClick={handleDismiss}
          className="flex h-6 w-6 shrink-0 items-center justify-center rounded-lg text-muted-foreground hover:text-foreground transition-colors"
          aria-label="Dismiss"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      </div>
    </div>
  )
}
