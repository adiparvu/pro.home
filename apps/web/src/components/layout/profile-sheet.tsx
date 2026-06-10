'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import {
  User, Palette, ShieldCheck, Languages, LogOut, ChevronRight,
} from 'lucide-react'
import type { User as SupabaseUser } from '@supabase/supabase-js'
import { createClient } from '@/lib/supabase/client'
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
import { BottomSheet } from '@/components/ui/bottom-sheet'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { getInitials } from '@/lib/utils'

const PROFILE_LINKS = [
  { label: 'Profile', description: 'Name, avatar & contact details', href: '/settings', icon: User },
  { label: 'Appearance', description: 'Theme & motion', href: '/settings/appearance', icon: Palette },
  { label: 'Security', description: 'Password & two-factor', href: '/settings/security', icon: ShieldCheck },
  { label: 'Language', description: 'App language', href: '/settings/language', icon: Languages },
]

/** Avatar trigger + bottom sheet with profile quick actions. */
export function ProfileSheet({ user }: { user: SupabaseUser }) {
  const router = useRouter()
  const confirmDialog = useConfirm()
  const [open, setOpen] = React.useState(false)

  const displayName =
    (user.user_metadata?.full_name as string | undefined) ??
    user.email?.split('@')[0] ??
    'User'
  const avatarUrl = user.user_metadata?.avatar_url as string | undefined

  async function handleSignOut() {
    const ok = await confirmDialog({
      title: 'Sign out?',
      description: 'You can sign back in at any time.',
      confirmLabel: 'Sign Out',
      destructive: true,
    })
    if (!ok) return
    setOpen(false)
    const supabase = createClient()
    await supabase.auth.signOut()
    router.push('/login')
    router.refresh()
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="focus-ring rounded-full"
        aria-label="Profile and quick settings"
      >
        <Avatar size="sm" status="online">
          {avatarUrl && <AvatarImage src={avatarUrl} alt={displayName} />}
          <AvatarFallback>{getInitials(displayName)}</AvatarFallback>
        </Avatar>
      </button>

      <BottomSheet open={open} onClose={() => setOpen(false)} title="Account" height="medium">
        {/* Identity */}
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

        {/* Quick links */}
        <div className="flex flex-col px-3 py-2">
          {PROFILE_LINKS.map((link) => {
            const Icon = link.icon
            return (
              <button
                key={link.href}
                type="button"
                onClick={() => {
                  setOpen(false)
                  router.push(link.href)
                }}
                className="flex items-center gap-3 rounded-xl px-3 py-3 text-left transition-colors hover:glass-light focus-ring"
              >
                <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl glass-light">
                  <Icon className="h-4 w-4 text-muted-foreground" />
                </div>
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-medium text-foreground">{link.label}</p>
                  <p className="text-xs text-muted-foreground">{link.description}</p>
                </div>
                <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
              </button>
            )
          })}

          {/* Sign out */}
          <button
            type="button"
            onClick={handleSignOut}
            className="mt-1 flex items-center gap-3 rounded-xl px-3 py-3 text-left transition-colors hover:bg-destructive/10 focus-ring"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-destructive/10">
              <LogOut className="h-4 w-4 text-destructive" />
            </div>
            <p className="text-sm font-medium text-destructive">Sign Out</p>
          </button>
        </div>
      </BottomSheet>
    </>
  )
}
