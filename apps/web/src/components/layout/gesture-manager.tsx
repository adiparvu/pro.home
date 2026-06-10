'use client'

import * as React from 'react'
import { useRouter, usePathname } from 'next/navigation'
import { RefreshCw } from 'lucide-react'
import { cn } from '@/lib/utils'

const EDGE_ZONE = 24
const BACK_THRESHOLD = 80
const REFRESH_THRESHOLD = 90

/**
 * Global mobile gestures:
 * - Edge-swipe right from the left screen edge → router.back()
 * - Pull down past the threshold at the top of the page → router.refresh()
 * Skipped while a sheet/dialog has scroll-locked the body.
 */
export function GestureManager() {
  const router = useRouter()
  const pathname = usePathname()
  const [pull, setPull] = React.useState(0)
  const [refreshing, setRefreshing] = React.useState(false)

  const start = React.useRef<{ x: number; y: number; edge: boolean; pulling: boolean } | null>(null)

  React.useEffect(() => {
    function overlayOpen() {
      return document.body.style.overflow === 'hidden'
    }

    function onTouchStart(e: TouchEvent) {
      if (overlayOpen()) return
      const t = e.touches[0]!
      start.current = {
        x: t.clientX,
        y: t.clientY,
        edge: t.clientX <= EDGE_ZONE,
        pulling: window.scrollY <= 0,
      }
    }

    function onTouchMove(e: TouchEvent) {
      const s = start.current
      if (!s || overlayOpen()) return
      const t = e.touches[0]!
      const dy = t.clientY - s.y

      // Pull-to-refresh indicator (rubber-banded)
      if (s.pulling && !s.edge && dy > 0 && window.scrollY <= 0) {
        setPull(Math.min(dy * 0.45, 110))
      }
    }

    function onTouchEnd(e: TouchEvent) {
      const s = start.current
      start.current = null
      if (!s || overlayOpen()) {
        setPull(0)
        return
      }
      const t = e.changedTouches[0]!
      const dx = t.clientX - s.x
      const dy = t.clientY - s.y

      // Edge-swipe back: horizontal, from the left edge, mostly straight
      if (s.edge && dx > BACK_THRESHOLD && Math.abs(dy) < dx * 0.6 && pathname !== '/') {
        if (navigator.vibrate) navigator.vibrate(8)
        router.back()
        setPull(0)
        return
      }

      // Pull-to-refresh
      if (s.pulling && dy * 0.45 >= REFRESH_THRESHOLD) {
        setRefreshing(true)
        if (navigator.vibrate) navigator.vibrate(8)
        router.refresh()
        setTimeout(() => {
          setRefreshing(false)
          setPull(0)
        }, 900)
      } else {
        setPull(0)
      }
    }

    window.addEventListener('touchstart', onTouchStart, { passive: true })
    window.addEventListener('touchmove', onTouchMove, { passive: true })
    window.addEventListener('touchend', onTouchEnd, { passive: true })
    return () => {
      window.removeEventListener('touchstart', onTouchStart)
      window.removeEventListener('touchmove', onTouchMove)
      window.removeEventListener('touchend', onTouchEnd)
    }
  }, [router, pathname])

  const visible = pull > 12 || refreshing
  const armed = pull >= REFRESH_THRESHOLD || refreshing

  return (
    <div
      className={cn(
        'pointer-events-none fixed left-1/2 z-40 -translate-x-1/2 transition-all duration-fast md:hidden',
        visible ? 'opacity-100' : 'opacity-0'
      )}
      style={{ top: `calc(env(safe-area-inset-top, 0px) + ${Math.min(pull * 0.5, 56) + 8}px)` }}
      aria-hidden="true"
    >
      <div
        className={cn(
          'flex h-9 w-9 items-center justify-center rounded-full glass-heavy',
          armed ? 'text-primary' : 'text-muted-foreground'
        )}
      >
        <RefreshCw
          className={cn('h-4 w-4', refreshing && 'animate-spin')}
          style={!refreshing ? { transform: `rotate(${pull * 2.2}deg)` } : undefined}
        />
      </div>
    </div>
  )
}
