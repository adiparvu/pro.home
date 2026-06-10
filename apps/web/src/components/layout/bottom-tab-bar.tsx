'use client'

import * as React from 'react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { Home, Building2, Sparkles, Users, LayoutGrid } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Badge } from '@/components/ui/badge'

const TAB_ITEMS = [
  { label: 'Home', href: '/', icon: Home, module: 'home' },
  { label: 'Property', href: '/property', icon: Building2, module: 'property' },
  { label: 'ARIA', href: '/aria', icon: Sparkles, module: 'aria', isCenter: true },
  { label: 'Family', href: '/family', icon: Users, module: 'family' },
  { label: 'More', href: '/more', icon: LayoutGrid, module: 'more' },
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

export function BottomTabBar({ unreadCount = 0 }: BottomTabBarProps) {
  const pathname = usePathname()

  return (
    <nav
      className={cn(
        'fixed bottom-0 left-0 right-0 z-[22] md:hidden',
        'glass-opaque',
        'border-t border-[rgba(255,255,255,0.10)]',
        'pb-safe'
      )}
      aria-label="Mobile navigation"
    >
      <div className="flex items-end justify-around px-2 pt-2 pb-2">
        {TAB_ITEMS.map((item) => {
          const isActive =
            item.href === '/'
              ? pathname === '/'
              : pathname.startsWith(item.href)
          const color = MODULE_COLORS[item.module]

          if ('isCenter' in item && item.isCenter) {
            return (
              <Link
                key={item.href}
                href={item.href}
                className={cn(
                  'relative flex -mt-5 h-14 w-14 flex-col items-center justify-center rounded-full',
                  'shadow-glow-aria',
                  'focus-ring',
                  'active:scale-[0.92] transition-transform duration-fast',
                  isActive
                    ? 'bg-[hsl(280,68%,47%)]'
                    : 'bg-[hsl(280,68%,38%)]'
                )}
                aria-current={isActive ? 'page' : undefined}
                aria-label={item.label}
              >
                <item.icon className="h-6 w-6 text-white" />
              </Link>
            )
          }

          const isMore = item.module === 'more'
          const showBadge = isMore && unreadCount > 0

          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                'relative flex min-w-[44px] flex-col items-center justify-center gap-1 py-1 px-2',
                'rounded-xl focus-ring',
                'active:scale-[0.90] transition-transform duration-fast'
              )}
              aria-current={isActive ? 'page' : undefined}
              aria-label={item.label}
            >
              <item.icon
                className={cn(
                  'h-6 w-6 transition-colors duration-fast',
                  isActive ? 'opacity-100' : 'opacity-50'
                )}
                style={isActive ? { color } : undefined}
              />
              {showBadge && (
                <Badge
                  variant="danger"
                  size="xs"
                  className="absolute -right-0.5 top-0"
                >
                  {unreadCount > 99 ? '99+' : unreadCount}
                </Badge>
              )}
              {isActive && (
                <span className="text-[10px] font-semibold" style={{ color }}>
                  {item.label}
                </span>
              )}
              {!isActive && (
                <span className="h-[10px]" aria-hidden="true" />
              )}
            </Link>
          )
        })}
      </div>
    </nav>
  )
}
