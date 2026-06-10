'use client'

import * as React from 'react'
import { createPortal } from 'react-dom'
import { cn } from '@/lib/utils'

export interface ContextMenuItem {
  label: string
  icon?: React.ComponentType<{ className?: string }>
  onSelect: () => void
  destructive?: boolean
  /** Renders a thicker iOS-style group separator above this item */
  divider?: boolean
}

interface ContextMenuProps {
  items: ContextMenuItem[]
  children: React.ReactNode
  /** Disable the menu entirely (e.g. for read-only roles) */
  disabled?: boolean
  className?: string
}

const LONG_PRESS_MS = 450
const MENU_WIDTH = 220

/**
 * iOS-style context menu. Long-press on touch devices, right-click on
 * desktop. Wrap any card or row:
 *
 *   <ContextMenu items={[{ label: 'Edit', icon: Pencil, onSelect: ... }]}>
 *     <TaskCard ... />
 *   </ContextMenu>
 */
export function ContextMenu({ items, children, disabled, className }: ContextMenuProps) {
  const [menu, setMenu] = React.useState<{ x: number; y: number } | null>(null)
  const [closing, setClosing] = React.useState(false)
  const pressTimer = React.useRef<ReturnType<typeof setTimeout> | null>(null)
  const pressStart = React.useRef<{ x: number; y: number } | null>(null)

  function openAt(clientX: number, clientY: number) {
    if (disabled || items.length === 0) return
    // Clamp horizontally; flip above the point if too close to the bottom
    const x = Math.min(Math.max(8, clientX - MENU_WIDTH / 2), window.innerWidth - MENU_WIDTH - 8)
    const estHeight = items.length * 44 + 16
    const y = clientY + estHeight > window.innerHeight - 16
      ? Math.max(16, clientY - estHeight - 8)
      : clientY + 8
    if (navigator.vibrate) navigator.vibrate(10)
    setMenu({ x, y })
  }

  function close() {
    setClosing(true)
    setTimeout(() => {
      setMenu(null)
      setClosing(false)
    }, 150)
  }

  function onContextMenu(e: React.MouseEvent) {
    if (disabled) return
    e.preventDefault()
    openAt(e.clientX, e.clientY)
  }

  function onTouchStart(e: React.TouchEvent) {
    if (disabled) return
    const t = e.touches[0]!
    pressStart.current = { x: t.clientX, y: t.clientY }
    pressTimer.current = setTimeout(() => openAt(t.clientX, t.clientY), LONG_PRESS_MS)
  }

  function cancelPress() {
    if (pressTimer.current) clearTimeout(pressTimer.current)
    pressTimer.current = null
    pressStart.current = null
  }

  function onTouchMove(e: React.TouchEvent) {
    if (!pressStart.current) return
    const t = e.touches[0]!
    // Cancel long-press if the finger drifts (user is scrolling)
    if (Math.abs(t.clientX - pressStart.current.x) > 10 || Math.abs(t.clientY - pressStart.current.y) > 10) {
      cancelPress()
    }
  }

  return (
    <>
      <div
        className={className}
        onContextMenu={onContextMenu}
        onTouchStart={onTouchStart}
        onTouchMove={onTouchMove}
        onTouchEnd={cancelPress}
        onTouchCancel={cancelPress}
      >
        {children}
      </div>

      {menu &&
        createPortal(
          <div className="fixed inset-0 z-[65]" role="menu">
            {/* Dismiss backdrop */}
            <div
              className={cn(
                'absolute inset-0 glass-frosted transition-opacity duration-150',
                closing ? 'opacity-0' : 'animate-fade-in'
              )}
              onClick={close}
              onContextMenu={(e) => { e.preventDefault(); close() }}
              aria-hidden="true"
            />

            {/* Menu */}
            <div
              className={cn(
                'absolute overflow-hidden rounded-2xl glass-opaque shadow-4',
                closing ? 'scale-95 opacity-0 transition-all duration-150' : 'animate-scale-in'
              )}
              style={{ left: menu.x, top: menu.y, width: MENU_WIDTH, transformOrigin: 'top center' }}
            >
              {items.map((item, i) => {
                const Icon = item.icon
                return (
                  <React.Fragment key={item.label}>
                    {item.divider && i > 0 && <div className="h-1.5 bg-black/20" />}
                    <button
                      type="button"
                      role="menuitem"
                      onClick={() => {
                        close()
                        // Let the close animation start before the action runs
                        setTimeout(item.onSelect, 80)
                      }}
                      className={cn(
                        'flex w-full items-center justify-between gap-3 px-4 py-2.5 text-left text-sm font-medium transition-colors hover:bg-white/5',
                        i > 0 && !item.divider && 'border-t border-border/30',
                        item.destructive ? 'text-destructive' : 'text-foreground'
                      )}
                    >
                      {item.label}
                      {Icon && <Icon className={cn('h-4 w-4', item.destructive ? 'text-destructive' : 'text-muted-foreground')} />}
                    </button>
                  </React.Fragment>
                )
              })}
            </div>
          </div>,
          document.body
        )}
    </>
  )
}
