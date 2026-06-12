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
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
import { BottomSheet } from '@/components/ui/bottom-sheet'
import { getInitials } from '@/lib/utils'
import { createClient } from '@/lib/supabase/client'
import type { Property } from '@/lib/supabase/types'

interface DashboardHeaderProps {
  user: SupabaseUser
  notificationCount?: number
  properties?: Property[]
  activeProperty?: Property
}

function getGreeting(): string {
  const hour = new Date().getHours()
  if (hour >= 5 && hour < 12) return 'Good morning'
  if (hour >= 12 && hour < 17) return 'Good afternoon'
  if (hour >= 17 && hour < 21) return 'Good evening'
  return 'Good night'
}

export function DashboardHeader({
  user,
  notificationCount = 0,
  properties = [],
  activeProperty,
}: DashboardHeaderProps) {
  const router = useRouter()
  const [profileOpen, setProfileOpen] = React.useState(false)

  const displayName =
    (user.user_metadata?.full_name as string | undefined) ??
    user.email?.split('@')[0] ??
    'User'
  const firstName = (displayName.split(' ')[0] ?? displayName).slice(0, 16)
  const avatarUrl = user.user_metadata?.avatar_url as string | undefined
  const greeting = getGreeting()
  const multipleProperties = properties.length > 1

  async function handleSignOut() {
    setProfileOpen(false)
    const supabase = createClient()
    await supabase.auth.signOut()
    router.push('/login')
    router.refresh()
  }

  return (
    <>
      <header className="sticky top-0 z-[22] glass-standard border-b border-[rgba(255,255,255,0.08)]">
        <div className="flex h-16 items-center justify-between px-4 md:px-6">
          {/* Left: Avatar + Greeting */}
          <div className="flex min-w-0 flex-1 items-center gap-3">
            <button
              type="button"
              onClick={() => setProfileOpen(true)}
              className="shrink-0 focus-ring rounded-full active:scale-95 transition-transform"
              aria-label="Profile and settings"
            >
              <Avatar size="md" status="online">
                {avatarUrl && <AvatarImage src={avatarUrl} alt={displayName} />}
                <AvatarFallback>{getInitials(displayName)}</AvatarFallback>
              </Avatar>
            </button>

            <div className="min-w-0 flex-1">
              <p className="text-[12px] text-muted-foreground leading-none mb-0.5">
                {greeting} 👋
              </p>
              <div className="flex items-center gap-1.5 min-w-0">
                <p className="text-[15px] font-bold text-foreground leading-tight">
                  {firstName}
                </p>
                {activeProperty && multipleProperties && (
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <button
                        className="flex items-center gap-0.5 rounded-lg px-1.5 py-0.5 glass-light text-[11px] text-muted-foreground hover:text-foreground transition-colors focus-ring"
                        aria-label="Switch property"
                      >
                        <span className="truncate max-w-[80px]">{activeProperty.name}</span>
                        <ChevronDown className="h-3 w-3 shrink-0" />
                      </button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="start" className="w-56">
                      <DropdownMenuLabel>My Properties</DropdownMenuLabel>
                      <DropdownMenuSeparator />
                      {properties.map((p) => (
                        <DropdownMenuItem
                          key={p.id}
                          onClick={async () => {
                            if (p.id === activeProperty.id) return
                            await fetch('/api/active-property', {
                              method: 'POST',
                              headers: { 'Content-Type': 'application/json' },
                              body: JSON.stringify({ propertyId: p.id }),
                            })
                            router.refresh()
                          }}
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
                  </DropdownMenu>
                )}
                {activeProperty && !multipleProperties && (
                  <span className="text-[11px] text-muted-foreground truncate hidden sm:inline">
                    · {activeProperty.name}
                  </span>
                )}
              </div>
            </div>
          </div>

          {/* Right: Notifications */}
          <NotificationsSheet count={notificationCount} />
        </div>
      </header>

      {/* Profile sheet — triggered by avatar tap */}
      <BottomSheet open={profileOpen} onClose={() => setProfileOpen(false)} title="Account" height="medium">
        <div className="flex items-center gap-3 border-b border-border/40 px-5 py-4">
          <Avatar size="md">
            {avatarUrl && <AvatarImage src={avatarUrl} alt={displayName} />}
            <AvatarFallback>{getInitials(displayName)}</AvatarFallback>
          </Avatar>
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold text-foreground">{displayName}</p>
            <p className="truncate text-xs text-muted-foreground">{user.email}</p>
          </div>
        </div>
        <div className="flex flex-col px-3 py-2">
          {[
            { label: 'Edit Profile', description: 'Name, avatar & contact details', href: '/settings' },
            { label: 'Appearance', description: 'Theme & motion', href: '/settings/appearance' },
            { label: 'Security', description: 'Password & two-factor', href: '/settings/security' },
            { label: 'Language', description: 'App language', href: '/settings/language' },
          ].map((link) => (
            <button
              key={link.href}
              type="button"
              onClick={() => { setProfileOpen(false); router.push(link.href) }}
              className="flex items-center gap-3 rounded-xl px-3 py-3 text-left transition-colors hover:glass-light focus-ring"
            >
              <div className="min-w-0 flex-1">
                <p className="text-sm font-semibold text-foreground">{link.label}</p>
                <p className="text-xs text-muted-foreground">{link.description}</p>
              </div>
            </button>
          ))}
          <button
            type="button"
            onClick={handleSignOut}
            className="mt-1 flex items-center gap-3 rounded-xl px-3 py-3 text-left transition-colors hover:bg-destructive/10 focus-ring"
          >
            <p className="text-sm font-semibold text-destructive">Sign Out</p>
          </button>
        </div>
      </BottomSheet>
    </>
  )
}
