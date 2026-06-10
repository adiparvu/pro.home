'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { ChevronDown, Building2, Check } from 'lucide-react'
import type { User as SupabaseUser } from '@supabase/supabase-js'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { NotificationsSheet } from '@/components/layout/notifications-sheet'
import { ProfileSheet } from '@/components/layout/profile-sheet'
import type { Property } from '@/lib/supabase/types'

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
  const router = useRouter()
  const today = new Date()
  const dateString = today.toLocaleDateString('en-US', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  })

  const multipleProperties = properties.length > 1

  return (
    <header className="sticky top-0 z-[22] glass-standard border-b border-[rgba(255,255,255,0.08)]">
      <div className="flex h-14 items-center justify-between px-4 md:px-6">
        {/* Left: Property selector / Date */}
        <div className="flex min-w-0 flex-1 items-center gap-3">
          {activeProperty ? (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
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
                  {multipleProperties && (
                    <ChevronDown className="h-3.5 w-3.5 shrink-0 text-muted-foreground group-hover:text-foreground transition-colors" />
                  )}
                </button>
              </DropdownMenuTrigger>
              {multipleProperties && (
                <DropdownMenuContent align="start" className="w-56">
                  <DropdownMenuLabel>My Properties</DropdownMenuLabel>
                  <DropdownMenuSeparator />
                  {properties.map((p) => (
                    <DropdownMenuItem
                      key={p.id}
                      onClick={() => router.push(p.id === activeProperty.id ? '/' : `/?p=${p.id}`)}
                    >
                      <Building2 className="h-4 w-4 shrink-0 text-muted-foreground" />
                      <div className="flex flex-1 flex-col min-w-0">
                        <span className="truncate text-sm">{p.name}</span>
                        <span className="truncate text-xs text-muted-foreground">{p.city}</span>
                      </div>
                      {p.id === activeProperty.id && (
                        <Check className="h-3.5 w-3.5 shrink-0 text-primary" />
                      )}
                    </DropdownMenuItem>
                  ))}
                </DropdownMenuContent>
              )}
            </DropdownMenu>
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
          <NotificationsSheet count={notificationCount} />
          <ProfileSheet user={user} />
        </div>
      </div>
    </header>
  )
}
