'use client'

import * as React from 'react'
import { createPortal } from 'react-dom'
import { X } from 'lucide-react'
import { cn } from '@/lib/utils'

export type BottomSheetHeight = 'small' | 'medium' | 'large'

interface BottomSheetProps {
  open: boolean
  onClose: () => void
  title?: string
  /** Optional element rendered on the right side of the header (e.g. an action button) */
  headerAction?: React.ReactNode
  height?: BottomSheetHeight
  children: React.ReactNode
  /** Sticky footer rendered below the scrollable content, inside the safe area */
  footer?: React.ReactNode
}

const HEIGHT_CLASSES: Record<BottomSheetHeight, string> = {
  small: 'max-h-[40dvh]',
  medium: 'max-h-[65dvh]',
  large: 'max-h-[92dvh]',
}

const CLOSE_MS = 260
const DISMISS_THRESHOLD = 90

/**
 * Global iOS-style bottom sheet. All secondary content — filters, quick
 * actions, previews, confirmations beyond simple alerts — opens through this
 * component rather than navigating to a new page.
 */
export function BottomSheet({
  open,
  onClose,
  title,
  headerAction,
  height = 'medium',
  children,
  footer,
}: BottomSheetProps) {
  const [mounted, setMounted] = React.useState(false)
  const [closing, setClosing] = React.useState(false)
  const [dragY, setDragY] = React.useState(0)
  const dragStart = React.useRef<number | null>(null)
  const sheetRef = React.useRef<HTMLDivElement>(null)

  React.useEffect(() => setMounted(true), [])

  const requestClose = React.useCallback(() => {
    setClosing(true)
    setTimeout(() => {
      setClosing(false)
      setDragY(0)
      onClose()
    }, CLOSE_MS)
  }, [onClose])

  // Escape to dismiss
  React.useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') requestClose()
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [open, requestClose])

  // Scroll lock
  React.useEffect(() => {
    if (!open) return
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => { document.body.style.overflow = prev }
  }, [open])

  // Swipe-down to dismiss (drag on grabber/header)
  function onTouchStart(e: React.TouchEvent) {
    dragStart.current = e.touches[0]!.clientY
  }
  function onTouchMove(e: React.TouchEvent) {
    if (dragStart.current === null) return
    const delta = e.touches[0]!.clientY - dragStart.current
    setDragY(Math.max(0, delta))
  }
  function onTouchEnd() {
    if (dragY > DISMISS_THRESHOLD) {
      requestClose()
    } else {
      setDragY(0)
    }
    dragStart.current = null
  }

  if (!mounted || !open) return null

  return createPortal(
    <div className="fixed inset-0 z-[60] flex items-end justify-center" role="dialog" aria-modal="true" aria-label={title}>
      {/* Backdrop blur */}
      <div
        className={cn(
          'absolute inset-0 glass-frosted transition-opacity',
          closing ? 'opacity-0 duration-[260ms]' : 'animate-fade-in'
        )}
        onClick={requestClose}
        aria-hidden="true"
      />

      {/* Panel */}
      <div
        ref={sheetRef}
        className={cn(
          'relative z-10 flex w-full max-w-lg flex-col',
          'rounded-t-[20px] glass-opaque shadow-4',
          HEIGHT_CLASSES[height],
          !closing && dragY === 0 && 'animate-slide-up',
          closing && 'transition-transform duration-[260ms] ease-in translate-y-full'
        )}
        style={dragY > 0 && !closing ? { transform: `translateY(${dragY}px)`, transition: 'none' } : undefined}
      >
        {/* Grabber */}
        <div
          className="flex shrink-0 cursor-grab touch-none justify-center pt-3 pb-1 active:cursor-grabbing"
          onTouchStart={onTouchStart}
          onTouchMove={onTouchMove}
          onTouchEnd={onTouchEnd}
        >
          <div className="h-[5px] w-9 rounded-full bg-muted-foreground/30" />
        </div>

        {/* Fixed header — close (X) left, centered title, optional action right */}
        {(title || headerAction) && (
          <div
            className="relative flex shrink-0 items-center justify-center border-b border-border/40 px-12 py-3 touch-none"
            onTouchStart={onTouchStart}
            onTouchMove={onTouchMove}
            onTouchEnd={onTouchEnd}
          >
            <button
              type="button"
              onClick={requestClose}
              className="absolute left-3 flex h-8 w-8 items-center justify-center rounded-full glass-light text-muted-foreground transition-colors hover:text-foreground focus-ring"
              aria-label="Close"
            >
              <X className="h-4 w-4" />
            </button>
            {title && (
              <p className="truncate text-base font-semibold text-foreground">{title}</p>
            )}
            {headerAction && <div className="absolute right-3">{headerAction}</div>}
          </div>
        )}

        {/* Scrollable content */}
        <div className={cn('flex-1 overflow-y-auto overscroll-contain', !footer && 'pb-safe')}>
          {children}
        </div>

        {/* Sticky footer */}
        {footer && (
          <div className="shrink-0 border-t border-border/40 px-4 py-3 pb-safe">
            {footer}
          </div>
        )}
      </div>
    </div>,
    document.body
  )
}
