'use client'

import * as React from 'react'
import { usePathname, useRouter } from 'next/navigation'
import {
  Plus, Wrench, Archive, Banknote, FolderOpen, Leaf, CalendarDays, Zap, ChevronRight,
} from 'lucide-react'
import { BottomSheet } from '@/components/ui/bottom-sheet'
import { getCapabilities } from '@/lib/permissions'
import type { UserRole } from '@/lib/supabase/types'
import { cn } from '@/lib/utils'

interface QuickAction {
  label: string
  description: string
  href: string
  icon: React.ComponentType<{ className?: string; style?: React.CSSProperties }>
  color: string
  enabled: (caps: ReturnType<typeof getCapabilities>) => boolean
}

const QUICK_ACTIONS: QuickAction[] = [
  {
    label: 'New Task',
    description: 'Maintenance, repair or inspection',
    href: '/maintenance/new',
    icon: Wrench,
    color: 'hsl(22,68%,48%)',
    enabled: (c) => c.createTask,
  },
  {
    label: 'New Inventory Item',
    description: 'Track an appliance or belonging',
    href: '/inventory/new',
    icon: Archive,
    color: 'hsl(185,62%,42%)',
    enabled: (c) => c.createInventory,
  },
  {
    label: 'Add Expense',
    description: 'Log a cost, income or budget',
    href: '/finances?add=1',
    icon: Banknote,
    color: 'hsl(45,75%,46%)',
    enabled: (c) => c.createFinance,
  },
  {
    label: 'Upload Document',
    description: 'Warranty, insurance or manual',
    href: '/documents?upload=1',
    icon: FolderOpen,
    color: 'hsl(220,52%,52%)',
    enabled: (c) => c.createDocument,
  },
  {
    label: 'New Plant',
    description: 'Add to your garden',
    href: '/garden/plants/new',
    icon: Leaf,
    color: 'hsl(120,52%,40%)',
    enabled: (c) => c.createGarden,
  },
  {
    label: 'New Garden Task',
    description: 'Watering, pruning, fertilizing',
    href: '/garden/tasks/new',
    icon: CalendarDays,
    color: 'hsl(88,52%,42%)',
    enabled: (c) => c.createGarden,
  },
  {
    label: 'Add Energy Reading',
    description: 'Log a meter reading',
    href: '/energy?add=1',
    icon: Zap,
    color: 'hsl(152,62%,42%)',
    enabled: (c) => c.createEnergyReading,
  },
]

// Routes where the FAB would conflict with a primary full-screen flow
const HIDDEN_PATTERNS = [/\/new$/, /\/edit$/, /^\/aria/, /^\/onboarding/, /^\/inventory\/scan/]

export function QuickActionsFab({ role }: { role: UserRole | null }) {
  const [open, setOpen] = React.useState(false)
  const router = useRouter()
  const pathname = usePathname()

  const caps = getCapabilities(role)
  const actions = QUICK_ACTIONS.filter((a) => a.enabled(caps))

  if (actions.length === 0) return null
  if (HIDDEN_PATTERNS.some((p) => p.test(pathname))) return null

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label="Quick actions"
        className={cn(
          'fixed z-50 flex h-14 w-14 items-center justify-center rounded-full',
          'bg-primary text-white shadow-glow-home',
          'transition-transform duration-fast active:scale-90 hover:scale-105 focus-ring',
          'bottom-[96px] right-4 md:bottom-6 md:right-6'
        )}
      >
        <Plus className="h-6 w-6" />
      </button>

      <BottomSheet open={open} onClose={() => setOpen(false)} title="Create" height="medium">
        <div className="flex flex-col px-3 py-2">
          {actions.map((action) => {
            const Icon = action.icon
            return (
              <button
                key={action.href}
                type="button"
                onClick={() => {
                  setOpen(false)
                  router.push(action.href)
                }}
                className="flex items-center gap-3 rounded-xl px-3 py-3 text-left transition-colors hover:glass-light focus-ring"
              >
                <div
                  className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl"
                  style={{ background: `color-mix(in srgb, ${action.color} 15%, transparent)` }}
                >
                  <Icon className="h-5 w-5" style={{ color: action.color }} />
                </div>
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-semibold text-foreground">{action.label}</p>
                  <p className="text-xs text-muted-foreground">{action.description}</p>
                </div>
                <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
              </button>
            )
          })}
        </div>
      </BottomSheet>
    </>
  )
}
