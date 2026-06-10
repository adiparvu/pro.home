import * as React from 'react'
import Link from 'next/link'
import {
  Zap,
  ShieldCheck,
  ShieldOff,
  Wrench,
  Archive,
  Sparkles,
  ChevronRight,
  CheckCircle,
  FileText,
  Flower2,
  Droplets,
} from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'

interface DashboardWidgetGridProps {
  upcomingTasksCount: number
  overdueTasksCount: number
  inventoryCount: number
  recallCount: number
  ariaInsight: string
  expiringDocsCount: number
  latestEnergyValue: number | null
  latestEnergyUnit: string | null
  latestEnergyMeterType: string | null
  securityMode: string | null
  overdueWateringCount: number
  pendingGardenTasksCount: number
}

const METER_TYPE_LABELS: Record<string, string> = {
  electricity: 'Electric',
  gas: 'Gas',
  water: 'Water',
  solar: 'Solar',
  district_heating: 'Heat',
  other: 'Meter',
}

const SECURITY_MODE_LABELS: Record<string, string> = {
  disarmed: 'Disarmed',
  home: 'Armed Home',
  away: 'Armed Away',
  night: 'Armed Night',
  vacation: 'Vacation',
}

const ARMED_MODES = new Set(['home', 'away', 'night', 'vacation'])

export function DashboardWidgetGrid({
  upcomingTasksCount,
  overdueTasksCount,
  inventoryCount,
  recallCount,
  ariaInsight,
  expiringDocsCount,
  latestEnergyValue,
  latestEnergyUnit,
  latestEnergyMeterType,
  securityMode,
  overdueWateringCount,
  pendingGardenTasksCount,
}: DashboardWidgetGridProps) {
  return (
    <div className="flex flex-col gap-4">
      {/* Row 1: Energy + Security */}
      <div className="grid grid-cols-2 gap-4">
        <EnergyWidget
          value={latestEnergyValue}
          unit={latestEnergyUnit}
          meterType={latestEnergyMeterType}
        />
        <SecurityWidget mode={securityMode} />
      </div>

      {/* Row 2: Maintenance (full width) */}
      <MaintenanceWidget count={upcomingTasksCount} overdueCount={overdueTasksCount} />

      {/* Row 3: ARIA Insight */}
      <ARIAInsightCard insight={ariaInsight} />

      {/* Row 4: Inventory + Garden */}
      <div className="grid grid-cols-2 gap-4">
        <InventoryWidget count={inventoryCount} recallCount={recallCount} />
        <GardenWidget
          overdueWateringCount={overdueWateringCount}
          pendingTasksCount={pendingGardenTasksCount}
        />
      </div>

      {/* Row 5: Quick Actions */}
      <QuickActionsWidget expiringDocsCount={expiringDocsCount} />
    </div>
  )
}

function EnergyWidget({
  value,
  unit,
  meterType,
}: {
  value: number | null
  unit: string | null
  meterType: string | null
}) {
  const hasData = value !== null
  const meterLabel = meterType ? (METER_TYPE_LABELS[meterType] ?? 'Energy') : 'Energy'

  return (
    <Link href="/energy">
      <Card variant="default" hover padding="md" className="module-energy">
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <div className="flex h-8 w-8 items-center justify-center rounded-xl bg-[hsl(152,62%,38%)]/20">
              <Zap className="h-4 w-4 text-[hsl(152,62%,52%)]" />
            </div>
            <Badge variant={hasData ? 'success' : 'neutral'} size="xs" dot={hasData}>
              {hasData ? meterLabel : 'No data'}
            </Badge>
          </div>
          <div>
            {hasData ? (
              <div className="flex items-baseline gap-1">
                <span className="text-2xl font-bold tabular-nums text-foreground">
                  {value!.toLocaleString()}
                </span>
                {unit && <span className="text-sm text-muted-foreground">{unit}</span>}
              </div>
            ) : (
              <div className="text-2xl font-bold text-muted-foreground/40">—</div>
            )}
            <p className="text-xs text-muted-foreground uppercase tracking-wider mt-0.5">
              Energy
            </p>
          </div>
          <div className="flex items-center gap-1 text-xs text-muted-foreground">
            <Zap className="h-3 w-3" />
            <span>{hasData ? 'Latest reading' : 'No readings yet'}</span>
          </div>
        </div>
      </Card>
    </Link>
  )
}

function SecurityWidget({ mode }: { mode: string | null }) {
  const isArmed = mode ? ARMED_MODES.has(mode) : false
  const displayMode = mode ? (SECURITY_MODE_LABELS[mode] ?? mode) : 'Not configured'
  const hasData = mode !== null

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
              {isArmed
                ? <ShieldOff className="h-4 w-4 text-[hsl(0,68%,58%)]" />
                : <ShieldCheck className="h-4 w-4 text-muted-foreground" />
              }
            </div>
            <Badge
              variant={isArmed ? 'danger' : hasData ? 'success' : 'neutral'}
              size="xs"
              dot={hasData}
            >
              {isArmed ? 'Armed' : hasData ? 'Safe' : 'N/A'}
            </Badge>
          </div>
          <div>
            <div className="text-base font-semibold text-foreground truncate">
              {displayMode}
            </div>
            <p className="text-xs text-muted-foreground uppercase tracking-wider mt-0.5">
              Security
            </p>
          </div>
          <div className="flex items-center gap-1 text-xs text-muted-foreground">
            <CheckCircle className="h-3 w-3" />
            <span>{hasData ? (isArmed ? 'System armed' : 'All clear') : 'Tap to configure'}</span>
          </div>
        </div>
      </Card>
    </Link>
  )
}

function MaintenanceWidget({ count, overdueCount }: { count: number; overdueCount: number }) {
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
            {overdueCount > 0 && (
              <Badge variant="critical" size="sm">
                {overdueCount} overdue
              </Badge>
            )}
            {overdueCount === 0 && count > 0 && (
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

function ARIAInsightCard({ insight }: { insight: string }) {
  return (
    <Card
      variant="heavy"
      padding="md"
      className="border-l-2 border-l-[hsl(280,68%,57%)] overflow-hidden relative"
    >
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
            {insight}
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

function InventoryWidget({ count, recallCount }: { count: number; recallCount: number }) {
  return (
    <Link href="/inventory">
      <Card variant="default" hover padding="md" className="module-inventory">
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <div className="flex h-8 w-8 items-center justify-center rounded-xl bg-[hsl(185,62%,38%)]/20">
              <Archive className="h-4 w-4 text-[hsl(185,62%,52%)]" />
            </div>
            {recallCount > 0 && (
              <Badge variant="critical" size="xs">{recallCount} recall</Badge>
            )}
          </div>
          <div>
            <div className="flex items-baseline gap-1">
              <span className="text-2xl font-bold tabular-nums text-foreground">{count}</span>
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

function GardenWidget({
  overdueWateringCount,
  pendingTasksCount,
}: {
  overdueWateringCount: number
  pendingTasksCount: number
}) {
  const needsAttention = overdueWateringCount > 0

  return (
    <Link href="/garden">
      <Card variant="default" hover padding="md" className="module-garden">
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <div
              className="flex h-8 w-8 items-center justify-center rounded-xl"
              style={{ background: 'hsl(120,52%,36%,0.2)' }}
            >
              <Flower2 className="h-4 w-4" style={{ color: 'hsl(120,52%,52%)' }} />
            </div>
            {needsAttention && (
              <Badge variant="warning" size="xs" dot>
                {overdueWateringCount} due
              </Badge>
            )}
          </div>
          <div>
            <div className="flex items-baseline gap-1">
              {needsAttention ? (
                <>
                  <span className="text-2xl font-bold tabular-nums text-foreground">
                    {overdueWateringCount}
                  </span>
                  <span className="text-sm text-muted-foreground">watering</span>
                </>
              ) : (
                <div className="text-2xl font-bold text-muted-foreground/40">—</div>
              )}
            </div>
            <p className="text-xs text-muted-foreground uppercase tracking-wider mt-0.5">
              Garden
            </p>
          </div>
          <div className="flex items-center gap-1 text-xs text-muted-foreground">
            <Droplets className="h-3 w-3" />
            <span>
              {pendingTasksCount > 0
                ? `${pendingTasksCount} task${pendingTasksCount !== 1 ? 's' : ''} pending`
                : needsAttention
                  ? 'Plants need water'
                  : 'All good'}
            </span>
          </div>
        </div>
      </Card>
    </Link>
  )
}

function QuickActionsWidget({ expiringDocsCount }: { expiringDocsCount: number }) {
  return (
    <Card variant="default" padding="md">
      <div className="flex flex-col gap-2">
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
          Quick Actions
        </p>
        <div className="grid grid-cols-2 gap-x-2 gap-y-1">
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
            href="/documents"
            className="flex items-center gap-2 rounded-lg px-2 py-1.5 hover:bg-[var(--color-hover)] transition-colors duration-fast focus-ring text-sm text-muted-foreground hover:text-foreground"
          >
            <span className="flex items-center gap-2 min-w-0">
              <FileText className="h-3.5 w-3.5 shrink-0" />
              Documents
            </span>
            {expiringDocsCount > 0 && (
              <Badge variant="warning" size="xs">{expiringDocsCount}</Badge>
            )}
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
