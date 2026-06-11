'use client'

import * as React from 'react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { User, Palette, Globe, Shield, Webhook } from 'lucide-react'
import { cn } from '@/lib/utils'

const TABS = [
  { id: 'profile',      label: 'Profile',      href: '/settings',              icon: User },
  { id: 'appearance',   label: 'Appearance',   href: '/settings/appearance',   icon: Palette },
  { id: 'language',     label: 'Language',     href: '/settings/language',     icon: Globe },
  { id: 'security',     label: 'Security',     href: '/settings/security',     icon: Shield },
  { id: 'integrations', label: 'Integrations', href: '/settings/integrations', icon: Webhook },
]

interface SettingsShellProps {
  activeTab: string
  children: React.ReactNode
}

export function SettingsShell({ children }: SettingsShellProps) {
  const pathname = usePathname()

  return (
    <div className="flex flex-1 flex-col md:flex-row">
      {/* Sidebar tabs (desktop) / top tabs (mobile) */}
      <nav
        className="flex md:flex-col gap-1 overflow-x-auto px-4 py-3 md:w-56 md:shrink-0 md:border-r md:border-border/50 md:px-3 md:py-4 scrollbar-hide"
        aria-label="Settings navigation"
      >
        {TABS.map(({ id, label, href, icon: Icon }) => {
          const isActive = pathname === href
          return (
            <Link
              key={id}
              href={href}
              className={cn(
                'flex shrink-0 items-center gap-2.5 rounded-xl px-3 py-2.5 text-sm transition-colors',
                'focus-ring',
                isActive
                  ? 'glass-standard text-foreground font-medium'
                  : 'text-muted-foreground hover:text-foreground hover:bg-white/5'
              )}
            >
              <Icon className="h-4 w-4 shrink-0" />
              <span className="whitespace-nowrap">{label}</span>
            </Link>
          )
        })}
      </nav>

      {/* Content */}
      <div className="flex-1 px-4 py-4 md:px-6 md:py-6">
        {children}
      </div>
    </div>
  )
}
