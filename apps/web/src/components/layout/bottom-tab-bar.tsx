'use client'

import * as React from 'react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { Home, Building2, Sparkles, Users, LayoutGrid } from 'lucide-react'
import { useTranslations } from 'next-intl'
import { useScrollDirection } from '@/hooks/use-scroll-direction'
import { useSlidingThumb } from '@/hooks/use-sliding-thumb'
import { cn } from '@/lib/utils'
import { Badge } from '@/components/ui/badge'

const TAB_ITEMS = [
  { key: 'home', href: '/', icon: Home, module: 'home' },
  { key: 'property', href: '/property', icon: Building2, module: 'property' },
  { key: 'aria', href: '/aria', icon: Sparkles, module: 'aria', isCenter: true },
  { key: 'family', href: '/family', icon: Users, module: 'family' },
  { key: 'more', href: '/more', icon: LayoutGrid, module: 'more' },
] as const

const MODULE_COLORS: Record<string, string> = {
  home: 'hsl(210, 75%, 52%)',
  property: 'hsl(36, 78%, 52%)',
  aria: 'hsl(280, 68%, 57%)',
  family: 'hsl(340, 68%, 56%)',
  more: 'hsl(220, 12%, 60%)',
}

interface BottomTabBarProps {
  unreadCount?: number
}

/**
 * Floating glass capsule navigation (mobile only). Sliding glass pill marks
 * the active tab; the whole capsule hides on scroll-down and springs back on
 * scroll-up, mirrored by the quick-actions FAB.
 */
export function BottomTabBar({ unreadCount = 0 }: BottomTabBarProps) {
  const pathname = usePathname()
  const t = useTranslations('navigation')
  const { hidden } = useScrollDirection()

  const activeHref =
    TAB_ITEMS.find((item) =>
      item.href === '/' ? pathname === '/' : pathname.startsWith(item.href)
    )?.href ?? ''

  const { containerRef, setItemRef, thumb } = useSlidingThumb(activeHref, [pathname])

  return (
    <nav
      className={cn(
        'fixed left-4 right-4 z-30 mx-auto max-w-[420px] md:hidden',
        'rounded-full glass-heavy',
        'transition-all duration-normal ease-spring-out motion-reduce:transition-opacity',
        'bottom-[calc(env(safe-area-inset-bottom,0px)+12px)]',
        hidden
          ? 'translate-y-[150%] opacity-0 motion-reduce:translate-y-0'
          : 'translate-y-0 opacity-100'
      )}
      aria-label="Mobile navigation"
    >
      <div ref={containerRef} className="relative flex items-center justify-around px-2 py-2">
        {/* Sliding active pill */}
        {thumb && activeHref && (
          <div
            className="absolute top-1.5 bottom-1.5 rounded-full glass-standard transition-all duration-normal ease-spring-out"
            style={{ left: thumb.left, width: thumb.width }}
            aria-hidden="true"
          />
        )}

        {TAB_ITEMS.map((item) => {
          const isActive = item.href === activeHref
          const color = MODULE_COLORS[item.module]
          const isCenter = 'isCenter' in item && item.isCenter
          const isMore = item.module === 'more'
          const showBadge = isMore && unreadCount > 0

          return (
            <Link
              key={item.href}
              ref={setItemRef(item.href)}
              href={item.href}
              className={cn(
                'relative z-10 flex h-12 min-w-[52px] flex-col items-center justify-center gap-0.5 rounded-full px-3',
                'focus-ring active:scale-[0.90] transition-transform duration-fast'
              )}
              aria-current={isActive ? 'page' : undefined}
              aria-label={t(item.key)}
            >
              {isCenter ? (
                <span
                  className={cn(
                    'flex h-9 w-9 items-center justify-center rounded-full shadow-glow-aria transition-colors duration-fast',
                    isActive ? 'bg-[hsl(280,68%,47%)]' : 'bg-[hsl(280,68%,38%)]'
                  )}
                >
                  <item.icon className="h-5 w-5 text-white" />
                </span>
              ) : (
                <>
                  <item.icon
                    className={cn(
                      'h-6 w-6 transition-all duration-fast',
                      isActive ? 'opacity-100' : 'opacity-50'
                    )}
                    style={isActive ? { color } : undefined}
                  />
                  {isActive && (
                    <span className="text-[10px] font-semibold leading-none" style={{ color }}>
                      {t(item.key)}
                    </span>
                  )}
                </>
              )}
              {showBadge && (
                <Badge variant="danger" size="xs" className="absolute right-1 top-0.5">
                  {unreadCount > 99 ? '99+' : unreadCount}
                </Badge>
              )}
            </Link>
          )
        })}
      </div>
    </nav>
  )
}
