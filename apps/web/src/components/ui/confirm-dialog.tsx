'use client'

import * as React from 'react'
import { createPortal } from 'react-dom'
import { cn } from '@/lib/utils'

export interface ConfirmOptions {
  title: string
  description?: string
  confirmLabel?: string
  cancelLabel?: string
  /** Renders the confirm button in red and emphasises caution */
  destructive?: boolean
}

type Resolver = (confirmed: boolean) => void

interface ConfirmContextValue {
  confirm: (options: ConfirmOptions) => Promise<boolean>
}

const ConfirmContext = React.createContext<ConfirmContextValue | null>(null)

/**
 * Global confirmation dialog. Use for delete, logout, archive, approval and
 * other critical actions instead of window.confirm.
 *
 *   const confirm = useConfirm()
 *   if (!(await confirm({ title: 'Delete task?', destructive: true }))) return
 */
export function useConfirm() {
  const ctx = React.useContext(ConfirmContext)
  if (!ctx) throw new Error('useConfirm must be used within <ConfirmProvider>')
  return ctx.confirm
}

export function ConfirmProvider({ children }: { children: React.ReactNode }) {
  const [options, setOptions] = React.useState<ConfirmOptions | null>(null)
  const [closing, setClosing] = React.useState(false)
  const resolverRef = React.useRef<Resolver | null>(null)

  const confirm = React.useCallback((opts: ConfirmOptions) => {
    return new Promise<boolean>((resolve) => {
      resolverRef.current = resolve
      setOptions(opts)
    })
  }, [])

  function settle(confirmed: boolean) {
    setClosing(true)
    setTimeout(() => {
      resolverRef.current?.(confirmed)
      resolverRef.current = null
      setOptions(null)
      setClosing(false)
    }, 180)
  }

  return (
    <ConfirmContext.Provider value={{ confirm }}>
      {children}
      {options && (
        <ConfirmDialog options={options} closing={closing} onSettle={settle} />
      )}
    </ConfirmContext.Provider>
  )
}

function ConfirmDialog({
  options,
  closing,
  onSettle,
}: {
  options: ConfirmOptions
  closing: boolean
  onSettle: (confirmed: boolean) => void
}) {
  React.useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onSettle(false)
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Scroll lock while open
  React.useEffect(() => {
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => { document.body.style.overflow = prev }
  }, [])

  return createPortal(
    <div className="fixed inset-0 z-[70] flex items-center justify-center px-8" role="alertdialog" aria-modal="true" aria-label={options.title}>
      {/* Backdrop */}
      <div
        className={cn(
          'absolute inset-0 glass-frosted transition-opacity duration-[180ms]',
          closing ? 'opacity-0' : 'animate-fade-in'
        )}
        aria-hidden="true"
      />

      {/* iOS-style alert card */}
      <div
        className={cn(
          'relative z-10 w-full max-w-[280px] overflow-hidden rounded-2xl glass-opaque shadow-4',
          closing
            ? 'scale-95 opacity-0 transition-all duration-[180ms]'
            : 'animate-scale-in'
        )}
      >
        <div className="px-5 pb-4 pt-5 text-center">
          <p className="text-base font-semibold text-foreground">{options.title}</p>
          {options.description && (
            <p className="mt-1.5 text-sm leading-snug text-muted-foreground">{options.description}</p>
          )}
        </div>

        {/* Button row — iOS hairline-separated */}
        <div className="grid grid-cols-2 border-t border-border/40">
          <button
            type="button"
            onClick={() => onSettle(false)}
            className="border-r border-border/40 py-3 text-sm font-medium text-foreground transition-colors hover:bg-white/5 focus-ring"
          >
            {options.cancelLabel ?? 'Cancel'}
          </button>
          <button
            type="button"
            onClick={() => onSettle(true)}
            className={cn(
              'py-3 text-sm font-semibold transition-colors hover:bg-white/5 focus-ring',
              options.destructive ? 'text-destructive' : 'text-primary'
            )}
          >
            {options.confirmLabel ?? 'Confirm'}
          </button>
        </div>
      </div>
    </div>,
    document.body
  )
}
