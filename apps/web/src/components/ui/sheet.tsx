'use client'

import * as React from 'react'
import { X } from 'lucide-react'
import { cn } from '@/lib/utils'

interface SheetProps {
  open: boolean
  onClose: () => void
  title?: string
  children: React.ReactNode
  side?: 'bottom' | 'right'
}

export function Sheet({ open, onClose, title, children, side = 'bottom' }: SheetProps) {
  React.useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose()
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [open, onClose])

  // Prevent scroll when open
  React.useEffect(() => {
    document.body.style.overflow = open ? 'hidden' : ''
    return () => { document.body.style.overflow = '' }
  }, [open])

  if (!open) return null

  if (side === 'right') {
    return (
      <div className="fixed inset-0 z-50 flex justify-end" role="dialog" aria-modal="true">
        {/* Backdrop */}
        <div
          className="absolute inset-0 glass-frosted"
          onClick={onClose}
          aria-hidden="true"
        />
        {/* Panel */}
        <div className="relative z-10 flex h-full w-full max-w-sm flex-col glass-opaque animate-slide-down md:animate-none">
          {title && (
            <div className="flex items-center justify-between border-b border-border/50 px-5 py-4">
              <p className="text-base font-bold text-foreground">{title}</p>
              <button
                type="button"
                onClick={onClose}
                className="flex h-8 w-8 items-center justify-center rounded-lg text-muted-foreground hover:text-foreground transition-colors focus-ring"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
          )}
          <div className="flex-1 overflow-y-auto">{children}</div>
        </div>
      </div>
    )
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end" role="dialog" aria-modal="true">
      {/* Backdrop */}
      <div
        className="absolute inset-0 glass-frosted"
        onClick={onClose}
        aria-hidden="true"
      />
      {/* Panel */}
      <div className="relative z-10 w-full rounded-t-3xl glass-opaque animate-slide-up max-h-[92dvh] flex flex-col">
        {/* Drag handle */}
        <div className="flex justify-center pt-3 pb-1">
          <div className="h-1 w-10 rounded-full bg-muted-foreground/30" />
        </div>
        {title && (
          <div className="flex items-center justify-between px-5 py-3 border-b border-border/50">
            <p className="text-base font-bold text-foreground">{title}</p>
            <button
              type="button"
              onClick={onClose}
              className="flex h-8 w-8 items-center justify-center rounded-lg text-muted-foreground hover:text-foreground transition-colors focus-ring"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        )}
        <div className="flex-1 overflow-y-auto overscroll-contain pb-safe">
          {children}
        </div>
      </div>
    </div>
  )
}
