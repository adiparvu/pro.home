'use client'

import * as React from 'react'
import Link from 'next/link'
import { Bell, ChevronDown, User } from 'lucide-react'
import type { User as SupabaseUser } from '@supabase/supabase-js'
import { Button } from '@/components/ui/button'
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import type { Property } from '@/lib/supabase/types'
import { getInitials, formatDate } from '@/lib/utils'

interface DashboardHeaderProps {
  user: SupabaseUser
  notificationCount?: number
  properties?: Property[]
  activeProperty?: Property
}

export function DashboardHeader({
  user,
  notificationCount = 0,
  properties = [],
  activeProperty,
}: DashboardHeaderProps) {
  const today = new Date()
  const dateString = today.toLocaleDateString('en-US', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  })

  const displayName =
    user.user_metadata?.full_name ??
    user.email?.split('@')[0] ??
    'User'

  const avatarUrl = user.user_metadata?.avatar_url as string | undefined

  return (
    <header className="sticky top-0 z-[22] glass-standard border-b border-[rgba(255,255,255,0.08)]">
      <div className="flex h-14 items-center justify-between px-4 md:px-6">
        {/* Left: Property selector / Date */}
        <div className="flex min-w-0 flex-1 items-center gap-3">
          {activeProperty ? (
            <button
              className="group flex min-w-0 items-center gap-2 rounded-xl px-2 py-1 hover:bg-[var(--color-hover)] transition-colors duration-fast focus-ring"
              aria-label="Switch property"
            >
              <div className="flex min-w-0 flex-col text-left">
                <span className="truncate text-sm font-semibold text-foreground leading-none">
                  {activeProperty.name}
                </span>
                <span className="truncate text-xs text-muted-foreground mt-0.5">
                  {activeProperty.city}
                </span>
              </div>
              <ChevronDown className="h-3.5 w-3.5 shrink-0 text-muted-foreground group-hover:text-foreground transition-colors" />
            </button>
          ) : (
            <div className="flex flex-col">
              <span className="text-sm font-medium text-foreground">PRV HOUSE</span>
              <span className="text-xs text-muted-foreground">{dateString}</span>
            </div>
          )}
        </div>

        {/* Center: Date (md+) */}
        <div className="hidden md:flex absolute left-1/2 -translate-x-1/2">
          <span className="text-sm text-muted-foreground">{dateString}</span>
        </div>

        {/* Right: Actions */}
        <div className="flex items-center gap-2">
          <Link
            href="/notifications"
            className="relative flex h-9 w-9 items-center justify-center rounded-xl hover:bg-[var(--color-hover)] transition-colors duration-fast focus-ring"
            aria-label={
              notificationCount > 0
                ? `${notificationCount} unread notifications`
                : 'Notifications'
            }
          >
            <Bell className="h-5 w-5 text-muted-foreground" />
            {notificationCount > 0 && (
              <span className="absolute -right-0.5 -top-0.5">
                <Badge variant="danger" size="xs">
                  {notificationCount > 99 ? '99+' : notificationCount}
                </Badge>
              </span>
            )}
          </Link>

          <Link
            href="/settings/profile"
            className="focus-ring rounded-full"
            aria-label="Profile settings"
          >
            <Avatar size="sm" status="online">
              {avatarUrl && <AvatarImage src={avatarUrl} alt={displayName} />}
              <AvatarFallback>{getInitials(displayName)}</AvatarFallback>
            </Avatar>
          </Link>
        </div>
      </div>
    </header>
  )
}
