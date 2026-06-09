import * as React from 'react'
import Link from 'next/link'
import {
  Zap,
  ShieldCheck,
  Wrench,
  Archive,
  Sparkles,
  ChevronRight,
  ArrowUp,
  ArrowDown,
  AlertTriangle,
  CheckCircle,
} from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import type { Property } from '@/lib/supabase/types'
import { cn } from '@/lib/utils'

interface DashboardWidgetGridProps {
  property: Property
  upcomingTasksCount: number
}

export function DashboardWidgetGrid({ property, upcomingTasksCount }: DashboardWidgetGridProps) {
  return (
    <div className="flex flex-col gap-4">
      {/* Row 1: Energy + Security */}
      <div className="grid grid-cols-2 gap-4">
        <EnergyWidget />
        <SecurityWidget />
      </div>

      {/* Row 2: Maintenance (full width) */}
      <MaintenanceWidget count={upcomingTasksCount} />

      {/* Row 3: ARIA Insight */}
      <ARIAInsightCard propertyName={property.name} />

      {/* Row 4: Inventory + Quick Actions */}
      <div className="grid grid-cols-2 gap-4">
        <InventoryWidget />
        <QuickActionsWidget />
      </div>
    </div>
  )
}

function EnergyWidget() {
  return (
    <Link href="/energy">
      <Card variant="default" hover padding="md" className="module-energy">
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <div className="flex h-8 w-8 items-center justify-center rounded-xl bg-[hsl(152,62%,38%)]/20">
              <Zap className="h-4 w-4 text-[hsl(152,62%,52%)]" />
            </div>
            <Badge variant="success" size="xs" dot>
              Live
            </Badge>
          </div>
          <div>
            <div className="flex items-baseline gap-1">
              <span className="text-2xl font-bold tabular-nums text-foreground">2.4</span>
              <span className="text-sm text-muted-foreground">kW</span>
            </div>
            <p className="text-xs text-muted-foreground uppercase tracking-wider mt-0.5">
              Energy
            </p>
          </div>
          <div className="flex items-center gap-1 text-xs text-[hsl(152,65%,48%)]">
            <ArrowDown className="h-3 w-3" />
            <span>12% vs yesterday</span>
          </div>
        </div>
      </Card>
    </Link>
  )
}

function SecurityWidget() {
  const isArmed = false

  return (
    <Link href="/security">
      <Card
        variant="default"
        hover
        padding="md"
        className={cn('module-security', isArmed && 'border-t-2 border-t-[hsl(0,68%,44%)]')}
      >
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <div className={cn(
              'flex h-8 w-8 items-center justify-center rounded-xl',
              isArmed ? 'bg-[hsl(0,68%,44%)]/20' : 'bg-[rgba(255,255,255,0.08)]'
            )}>
              <ShieldCheck className={cn(
                'h-4 w-4',
                isArmed ? 'text-[hsl(0,68%,58%)]' : 'text-muted-foreground'
              )} />
            </div>
            <Badge variant={isArmed ? 'danger' : 'success'} size="xs" dot>
              {isArmed ? 'Armed' : 'Safe'}
            </Badge>
          </div>
          <div>
            <div className="text-base font-semibold text-foreground">
              {isArmed ? 'Armed Away' : 'Disarmed'}
            </div>
            <p className="text-xs text-muted-foreground uppercase tracking-wider mt-0.5">
              Security
            </p>
          </div>
          <div className="flex items-center gap-1 text-xs text-muted-foreground">
            <CheckCircle className="h-3 w-3" />
            <span>All clear</span>
          </div>
        </div>
      </Card>
    </Link>
  )
}

function MaintenanceWidget({ count }: { count: number }) {
  return (
    <Link href="/maintenance">
      <Card variant="default" hover padding="md" className="module-maintenance">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-[hsl(22,68%,41%)]/20">
              <Wrench className="h-5 w-5 text-[hsl(22,68%,55%)]" />
            </div>
            <div>
              <div className="flex items-baseline gap-1.5">
                <span className="text-xl font-bold tabular-nums text-foreground">{count}</span>
                <span className="text-sm text-muted-foreground">upcoming</span>
              </div>
              <p className="text-xs text-muted-foreground uppercase tracking-wider">
                Maintenance
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {count > 0 && (
              <Badge variant="warning" size="sm">
                {count} task{count !== 1 ? 's' : ''}
              </Badge>
            )}
            <ChevronRight className="h-4 w-4 text-muted-foreground" />
          </div>
        </div>
      </Card>
    </Link>
  )
}

function ARIAInsightCard({ propertyName }: { propertyName: string }) {
  return (
    <Card
      variant="heavy"
      padding="md"
      className="border-l-2 border-l-[hsl(280,68%,57%)] overflow-hidden relative"
    >
      {/* ARIA glow */}
      <div
        className="absolute inset-0 opacity-5 pointer-events-none"
        style={{
          background: 'radial-gradient(ellipse at 0% 50%, hsl(280, 68%, 57%), transparent 70%)',
        }}
        aria-hidden="true"
      />

      <div className="relative flex items-start gap-3">
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[hsl(280,68%,47%)]/20">
          <Sparkles className="h-4 w-4 text-[hsl(280,68%,67%)]" />
        </div>
        <div className="flex flex-1 flex-col gap-1 min-w-0">
          <div className="flex items-center gap-2">
            <span className="text-xs font-semibold uppercase tracking-wider text-[hsl(280,68%,67%)]">
              ARIA Insight
            </span>
          </div>
          <p className="text-sm text-foreground leading-relaxed">
            Your HVAC filter is due for replacement in 3 days. Based on your usage, ordering now would save you 2–3 days of reduced air quality.
          </p>
          <Link
            href="/aria"
            className="mt-1 inline-flex items-center gap-1 text-xs font-medium text-[hsl(280,68%,67%)] hover:text-[hsl(280,68%,77%)] transition-colors duration-fast focus-ring rounded"
          >
            Ask ARIA about this
            <ChevronRight className="h-3 w-3" />
          </Link>
        </div>
      </div>
    </Card>
  )
}

function InventoryWidget() {
  return (
    <Link href="/inventory">
      <Card variant="default" hover padding="md" className="module-inventory">
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <div className="flex h-8 w-8 items-center justify-center rounded-xl bg-[hsl(185,62%,38%)]/20">
              <Archive className="h-4 w-4 text-[hsl(185,62%,52%)]" />
            </div>
          </div>
          <div>
            <div className="flex items-baseline gap-1">
              <span className="text-2xl font-bold tabular-nums text-foreground">0</span>
            </div>
            <p className="text-xs text-muted-foreground uppercase tracking-wider mt-0.5">
              Items
            </p>
          </div>
          <div className="flex items-center gap-1 text-xs text-muted-foreground">
            <Archive className="h-3 w-3" />
            <span>Inventory</span>
          </div>
        </div>
      </Card>
    </Link>
  )
}

function QuickActionsWidget() {
  return (
    <Card variant="default" padding="md">
      <div className="flex flex-col gap-2">
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
          Quick Actions
        </p>
        <div className="flex flex-col gap-1.5">
          <Link
            href="/inventory/scan"
            className="flex items-center gap-2 rounded-lg px-2 py-1.5 hover:bg-[var(--color-hover)] transition-colors duration-fast focus-ring text-sm text-muted-foreground hover:text-foreground"
          >
            <Archive className="h-3.5 w-3.5 shrink-0" />
            M-SCAN™
          </Link>
          <Link
            href="/maintenance/new"
            className="flex items-center gap-2 rounded-lg px-2 py-1.5 hover:bg-[var(--color-hover)] transition-colors duration-fast focus-ring text-sm text-muted-foreground hover:text-foreground"
          >
            <Wrench className="h-3.5 w-3.5 shrink-0" />
            Add Task
          </Link>
          <Link
            href="/aria"
            className="flex items-center gap-2 rounded-lg px-2 py-1.5 hover:bg-[var(--color-hover)] transition-colors duration-fast focus-ring text-sm text-muted-foreground hover:text-foreground"
          >
            <Sparkles className="h-3.5 w-3.5 shrink-0" />
            Ask ARIA
          </Link>
        </div>
      </div>
    </Card>
  )
}
