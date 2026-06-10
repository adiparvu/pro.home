import * as React from 'react'
import Link from 'next/link'
import { ArrowUpRight, TrendingUp, TrendingDown, Minus } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import type { Property } from '@/lib/supabase/types'
import { cn } from '@/lib/utils'

interface HealthHeroCardProps {
  property: Property
  overdueTasksCount: number
  upcomingTasksCount: number
  recallCount: number
}

function getHealthVariant(score: number | null): {
  label: string
  variant: 'excellent' | 'good' | 'fair' | 'poor' | 'critical'
  color: string
} {
  if (!score) return { label: 'Unknown', variant: 'fair', color: 'hsl(220, 8%, 48%)' }
  if (score >= 85) return { label: 'Excellent', variant: 'excellent', color: 'hsl(152, 70%, 42%)' }
  if (score >= 70) return { label: 'Good', variant: 'good', color: 'hsl(96, 65%, 42%)' }
  if (score >= 50) return { label: 'Fair', variant: 'fair', color: 'hsl(45, 80%, 48%)' }
  if (score >= 25) return { label: 'Poor', variant: 'poor', color: 'hsl(22, 75%, 48%)' }
  return { label: 'Critical', variant: 'critical', color: 'hsl(0, 70%, 50%)' }
}

function HealthRing({
  score,
  size = 96,
  color,
}: {
  score: number
  size?: number
  color: string
}) {
  const strokeWidth = size * 0.083 // ~8px for 96px ring
  const r = (size - strokeWidth) / 2
  const circumference = 2 * Math.PI * r
  const offset = circumference * (1 - score / 100)
  const center = size / 2

  return (
    <svg
      width={size}
      height={size}
      viewBox={`0 0 ${size} ${size}`}
      aria-label={`Property health score: ${score} out of 100`}
      role="img"
    >
      {/* Background track */}
      <circle
        cx={center}
        cy={center}
        r={r}
        fill="none"
        stroke="rgba(255,255,255,0.06)"
        strokeWidth={strokeWidth}
      />
      {/* Score arc */}
      <circle
        cx={center}
        cy={center}
        r={r}
        fill="none"
        stroke={color}
        strokeWidth={strokeWidth}
        strokeDasharray={circumference}
        strokeDashoffset={offset}
        strokeLinecap="round"
        transform={`rotate(-90 ${center} ${center})`}
        className="transition-all duration-slower ease-out"
      />
      {/* Center score */}
      <text
        x={center}
        y={center + 8}
        textAnchor="middle"
        fill={color}
        fontSize={size * 0.229}
        fontWeight="700"
        fontFamily="-apple-system, BlinkMacSystemFont, 'Inter', sans-serif"
      >
        {score}
      </text>
    </svg>
  )
}

export function HealthHeroCard({ property, overdueTasksCount, upcomingTasksCount, recallCount }: HealthHeroCardProps) {
  const score = property.health_score
  const { label, variant, color } = getHealthVariant(score)

  const maintenanceScore = Math.max(20, 95 - overdueTasksCount * 15 - Math.min(upcomingTasksCount, 5))
  const safetyScore = Math.max(30, 95 - recallCount * 20)
  const energyScore = score ?? 65
  const maintenanceTrend: 'up' | 'down' | 'stable' =
    overdueTasksCount > 0 ? 'down' : upcomingTasksCount > 5 ? 'stable' : 'up'
  const safetyTrend: 'up' | 'down' | 'stable' = recallCount > 0 ? 'down' : 'up'

  return (
    <Card
      variant="heavy"
      padding="lg"
      className="relative overflow-hidden"
    >
      {/* Background glow */}
      <div
        className="absolute inset-0 opacity-5 pointer-events-none"
        style={{
          background: `radial-gradient(ellipse at center, ${color}, transparent 70%)`,
        }}
        aria-hidden="true"
      />

      <div className="relative flex items-center gap-6">
        {/* Health Ring */}
        <div className="shrink-0">
          {score !== null ? (
            <HealthRing score={score} size={96} color={color} />
          ) : (
            <div className="h-24 w-24 rounded-full bg-muted/20 flex items-center justify-center">
              <span className="text-sm text-muted-foreground">—</span>
            </div>
          )}
        </div>

        {/* Score Info */}
        <div className="flex flex-1 flex-col gap-1 min-w-0">
          <div className="flex items-center gap-2">
            <Badge variant={variant} size="sm" dot>
              {label}
            </Badge>
          </div>
          <h2 className="text-lg font-semibold text-foreground">
            Property Health
          </h2>
          <p className="text-sm text-muted-foreground">
            {property.health_updated_at
              ? `Updated ${getRelativeTime(property.health_updated_at)}`
              : 'Not yet calculated'}
          </p>
        </div>

        {/* View Report Link */}
        <Link
          href="/property/health"
          className="shrink-0 flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground transition-colors duration-fast focus-ring rounded-lg px-2 py-1"
          aria-label="View full health report"
        >
          <span className="hidden sm:inline">View Report</span>
          <ArrowUpRight className="h-4 w-4" />
        </Link>
      </div>

      {/* Factor Preview */}
      {score !== null && (
        <div className="mt-4 grid grid-cols-3 gap-3 pt-4 border-t border-[rgba(255,255,255,0.06)]">
          <FactorMini label="Maintenance" score={maintenanceScore} trend={maintenanceTrend} />
          <FactorMini label="Safety" score={safetyScore} trend={safetyTrend} />
          <FactorMini label="Energy" score={energyScore} trend="stable" />
        </div>
      )}
    </Card>
  )
}

function FactorMini({
  label,
  score,
  trend,
}: {
  label: string
  score: number
  trend: 'up' | 'down' | 'stable'
}) {
  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center justify-between">
        <span className="text-xs text-muted-foreground">{label}</span>
        {trend === 'up' && <TrendingUp className="h-3 w-3 text-[hsl(152,65%,48%)]" />}
        {trend === 'down' && <TrendingDown className="h-3 w-3 text-destructive" />}
        {trend === 'stable' && <Minus className="h-3 w-3 text-muted-foreground" />}
      </div>
      <div className="flex items-center gap-2">
        <div className="h-1.5 flex-1 rounded-full bg-[rgba(255,255,255,0.08)] overflow-hidden">
          <div
            className="h-full rounded-full transition-all duration-slow"
            style={{
              width: `${score}%`,
              background: score >= 70 ? 'hsl(152,65%,48%)' : score >= 50 ? 'hsl(45,80%,48%)' : 'hsl(0,70%,50%)',
            }}
          />
        </div>
        <span className="text-xs font-medium tabular-nums text-foreground w-7 text-right">
          {score}
        </span>
      </div>
    </div>
  )
}

function getRelativeTime(dateStr: string): string {
  const now = Date.now()
  const then = new Date(dateStr).getTime()
  const delta = now - then
  const minutes = Math.floor(delta / 60000)
  const hours = Math.floor(minutes / 60)
  const days = Math.floor(hours / 24)

  if (minutes < 60) return `${minutes}m ago`
  if (hours < 24) return `${hours}h ago`
  return `${days}d ago`
}
