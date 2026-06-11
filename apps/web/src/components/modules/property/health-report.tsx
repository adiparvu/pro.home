'use client'

import * as React from 'react'
import Link from 'next/link'
import {
  ArrowLeft,
  RefreshCw,
  Wrench,
  ShieldAlert,
  FileWarning,
  CheckCircle,
  TrendingUp,
  TrendingDown,
  Minus,
  AlertTriangle,
  Package,
  FileText,
} from 'lucide-react'
import type { Property, MaintenanceTask, InventoryItem, Document, PropertyHealthHistory } from '@/lib/supabase/types'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'

type OverdueTask = Pick<MaintenanceTask, 'id' | 'title' | 'priority' | 'due_date' | 'status' | 'category'>
type RecallItem = Pick<InventoryItem, 'id' | 'name' | 'brand' | 'model'>
type ExpiringDoc = Pick<Document, 'id' | 'name' | 'category' | 'expires_at'>

type HistoryPoint = Pick<PropertyHealthHistory, 'score' | 'recorded_at'>

interface HealthReportProps {
  property: Property
  overdueCount: number
  upcomingCount: number
  recallCount: number
  overdueTasks: OverdueTask[]
  recallItems: RecallItem[]
  expiringDocs: ExpiringDoc[]
  refreshScoreAction: () => Promise<void>
  scoreHistory: HistoryPoint[]
}

function getHealthLabel(score: number | null) {
  if (!score) return { label: 'Unknown', color: 'hsl(220, 8%, 48%)' }
  if (score >= 85) return { label: 'Excellent', color: 'hsl(152, 70%, 42%)' }
  if (score >= 70) return { label: 'Good', color: 'hsl(96, 65%, 42%)' }
  if (score >= 50) return { label: 'Fair', color: 'hsl(45, 80%, 48%)' }
  if (score >= 25) return { label: 'Poor', color: 'hsl(22, 75%, 48%)' }
  return { label: 'Critical', color: 'hsl(0, 70%, 50%)' }
}

function HealthRing({ score, size = 120, color }: { score: number; size?: number; color: string }) {
  const sw = size * 0.083
  const r = (size - sw) / 2
  const circ = 2 * Math.PI * r
  const offset = circ * (1 - score / 100)
  const c = size / 2
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
      <circle cx={c} cy={c} r={r} fill="none" stroke="rgba(255,255,255,0.06)" strokeWidth={sw} />
      <circle
        cx={c} cy={c} r={r} fill="none" stroke={color} strokeWidth={sw}
        strokeDasharray={circ} strokeDashoffset={offset}
        strokeLinecap="round" transform={`rotate(-90 ${c} ${c})`}
        className="transition-all duration-slower ease-out"
      />
      <text x={c} y={c + 9} textAnchor="middle" fill={color}
        fontSize={size * 0.22} fontWeight="700"
        fontFamily="-apple-system, BlinkMacSystemFont, 'Inter', sans-serif">
        {score}
      </text>
    </svg>
  )
}

function FactorCard({
  label, score, trend, description,
}: {
  label: string
  score: number
  trend: 'up' | 'down' | 'stable'
  description: string
}) {
  const color = score >= 70 ? 'hsl(152,65%,48%)' : score >= 50 ? 'hsl(45,80%,48%)' : 'hsl(0,70%,50%)'
  return (
    <Card variant="default" padding="md">
      <div className="flex flex-col gap-2">
        <div className="flex items-center justify-between">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">{label}</p>
          {trend === 'up' && <TrendingUp className="h-3.5 w-3.5 text-[hsl(152,65%,48%)]" />}
          {trend === 'down' && <TrendingDown className="h-3.5 w-3.5 text-destructive" />}
          {trend === 'stable' && <Minus className="h-3.5 w-3.5 text-muted-foreground" />}
        </div>
        <div className="flex items-end gap-2">
          <span className="text-2xl font-bold tabular-nums" style={{ color }}>{score}</span>
          <span className="text-xs text-muted-foreground mb-1">/ 100</span>
        </div>
        <div className="h-1.5 rounded-full bg-white/6 overflow-hidden">
          <div
            className="h-full rounded-full transition-all duration-slow"
            style={{ width: `${score}%`, background: color }}
          />
        </div>
        <p className="text-xs text-muted-foreground">{description}</p>
      </div>
    </Card>
  )
}

export function HealthReport({
  property,
  overdueCount,
  upcomingCount,
  recallCount,
  overdueTasks,
  recallItems,
  expiringDocs,
  refreshScoreAction,
  scoreHistory,
}: HealthReportProps) {
  const [refreshing, setRefreshing] = React.useState(false)
  const score = property.health_score
  const { label, color } = getHealthLabel(score)

  const maintenanceScore = Math.max(20, 95 - overdueCount * 15 - Math.min(upcomingCount, 5))
  const safetyScore = Math.max(30, 95 - recallCount * 20)
  const energyScore = score ?? 65

  const maintenanceTrend: 'up' | 'down' | 'stable' =
    overdueCount > 0 ? 'down' : upcomingCount > 5 ? 'stable' : 'up'
  const safetyTrend: 'up' | 'down' | 'stable' = recallCount > 0 ? 'down' : 'up'

  const hasIssues = overdueCount > 0 || recallCount > 0 || expiringDocs.length > 0

  async function handleRefresh() {
    setRefreshing(true)
    await refreshScoreAction()
    setRefreshing(false)
  }

  return (
    <>
      <PageHeader title="Property Health" description={property.name} />

      <div className="flex flex-col gap-5 px-4 py-4 md:px-6 md:py-6">
        {/* Overall score */}
        <Card variant="heavy" padding="lg" className="relative overflow-hidden">
          <div
            className="absolute inset-0 opacity-5 pointer-events-none"
            style={{ background: `radial-gradient(ellipse at center, ${color}, transparent 70%)` }}
            aria-hidden="true"
          />
          <div className="relative flex items-center gap-6">
            <div className="shrink-0">
              {score !== null ? (
                <HealthRing score={score} size={112} color={color} />
              ) : (
                <div className="h-28 w-28 rounded-full bg-muted/20 flex items-center justify-center">
                  <span className="text-lg text-muted-foreground">—</span>
                </div>
              )}
            </div>
            <div className="flex flex-1 flex-col gap-1.5 min-w-0">
              <Badge
                variant={
                  score === null ? 'neutral'
                    : score >= 85 ? 'excellent'
                    : score >= 70 ? 'good'
                    : score >= 50 ? 'fair'
                    : score >= 25 ? 'poor'
                    : 'critical'
                }
                size="sm"
                dot
              >
                {label}
              </Badge>
              <h2 className="text-xl font-semibold text-foreground">Overall Health</h2>
              <p className="text-sm text-muted-foreground">
                {property.health_updated_at
                  ? `Updated ${getRelativeTime(property.health_updated_at)}`
                  : 'Score not yet computed'}
              </p>
              <form action={handleRefresh} className="mt-1">
                <Button
                  type="submit"
                  variant="secondary"
                  size="sm"
                  loading={refreshing}
                  onClick={handleRefresh}
                >
                  <RefreshCw className="h-3.5 w-3.5" />
                  Refresh Score
                </Button>
              </form>
            </div>
          </div>
        </Card>

        {/* Score history sparkline */}
        {scoreHistory.length >= 2 && (
          <ScoreHistoryChart history={scoreHistory} color={color} />
        )}

        {/* Factor breakdown */}
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
            Factor Breakdown
          </p>
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <FactorCard
              label="Maintenance"
              score={maintenanceScore}
              trend={maintenanceTrend}
              description={
                overdueCount > 0
                  ? `${overdueCount} overdue task${overdueCount !== 1 ? 's' : ''}`
                  : upcomingCount > 0
                  ? `${upcomingCount} upcoming`
                  : 'All clear'
              }
            />
            <FactorCard
              label="Safety"
              score={safetyScore}
              trend={safetyTrend}
              description={
                recallCount > 0
                  ? `${recallCount} active recall${recallCount !== 1 ? 's' : ''}`
                  : 'No recalls'
              }
            />
            <FactorCard
              label="Energy"
              score={energyScore}
              trend="stable"
              description="Based on property score"
            />
          </div>
        </div>

        {/* Issues */}
        {hasIssues ? (
          <div>
            <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
              Issues to Address
            </p>
            <div className="flex flex-col gap-2">
              {overdueTasks.map((task) => (
                <Link key={task.id} href={`/maintenance/${task.id}`}>
                  <Card variant="default" hover padding="md">
                    <div className="flex items-center gap-3">
                      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-destructive/10">
                        <Wrench className="h-4 w-4 text-destructive" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-foreground truncate">{task.title}</p>
                        <p className="text-xs text-destructive">
                          Overdue{task.due_date ? ` · was due ${new Date(task.due_date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}` : ''}
                        </p>
                      </div>
                      <Badge variant="critical" size="xs" className="shrink-0">
                        {task.priority}
                      </Badge>
                    </div>
                  </Card>
                </Link>
              ))}

              {recallItems.map((item) => (
                <Link key={item.id} href={`/inventory/${item.id}`}>
                  <Card variant="default" hover padding="md">
                    <div className="flex items-center gap-3">
                      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-[hsl(22,75%,48%)]/10">
                        <Package className="h-4 w-4 text-[hsl(22,75%,48%)]" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-foreground truncate">{item.name}</p>
                        <p className="text-xs text-muted-foreground">
                          {[item.brand, item.model].filter(Boolean).join(' · ')}
                        </p>
                      </div>
                      <Badge variant="warning" size="xs" className="shrink-0">Recall</Badge>
                    </div>
                  </Card>
                </Link>
              ))}

              {expiringDocs.map((doc) => {
                const exp = new Date(doc.expires_at!)
                const daysLeft = Math.ceil((exp.getTime() - Date.now()) / (24 * 60 * 60 * 1000))
                return (
                  <Link key={doc.id} href="/documents">
                    <Card variant="default" hover padding="md">
                      <div className="flex items-center gap-3">
                        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-[hsl(45,80%,48%)]/10">
                          <FileText className="h-4 w-4 text-[hsl(45,80%,48%)]" />
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium text-foreground truncate">{doc.name}</p>
                          <p className="text-xs text-muted-foreground capitalize">{doc.category}</p>
                        </div>
                        <Badge variant="warning" size="xs" className="shrink-0">
                          {daysLeft}d left
                        </Badge>
                      </div>
                    </Card>
                  </Link>
                )
              })}
            </div>
          </div>
        ) : (
          <Card variant="default" padding="lg">
            <div className="flex flex-col items-center gap-3 py-4 text-center">
              <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-[hsl(152,62%,42%)]/10">
                <CheckCircle className="h-6 w-6 text-[hsl(152,62%,48%)]" />
              </div>
              <div>
                <p className="text-sm font-semibold text-foreground">No issues found</p>
                <p className="text-xs text-muted-foreground mt-0.5">
                  Your home is in great shape. Keep up with maintenance to stay ahead.
                </p>
              </div>
            </div>
          </Card>
        )}

        {/* Tips */}
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
            How to Improve
          </p>
          <div className="flex flex-col gap-2">
            {overdueCount > 0 && (
              <TipCard
                icon={Wrench}
                color="hsl(22,68%,45%)"
                title="Complete overdue tasks"
                description="Each overdue task reduces your maintenance score by 15 points."
                href="/maintenance"
              />
            )}
            {recallCount > 0 && (
              <TipCard
                icon={ShieldAlert}
                color="hsl(0,68%,44%)"
                title="Resolve safety recalls"
                description="Check manufacturer websites for recall remedies or replacements."
                href="/inventory"
              />
            )}
            {expiringDocs.length > 0 && (
              <TipCard
                icon={FileWarning}
                color="hsl(45,80%,48%)"
                title="Renew expiring documents"
                description="Keep insurance, warranties, and permits up to date."
                href="/documents"
              />
            )}
            <TipCard
              icon={AlertTriangle}
              color="hsl(220,62%,52%)"
              title="Log your expenses"
              description="Tracking maintenance costs helps predict future home needs."
              href="/finances"
            />
          </div>
        </div>

        <Link
          href="/"
          className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground transition-colors self-start"
        >
          <ArrowLeft className="h-3.5 w-3.5" />
          Back to Dashboard
        </Link>
      </div>
    </>
  )
}

function ScoreHistoryChart({ history, color }: { history: HistoryPoint[]; color: string }) {
  const W = 300, H = 80
  const PAD = { top: 8, right: 8, bottom: 20, left: 28 }
  const chartW = W - PAD.left - PAD.right
  const chartH = H - PAD.top - PAD.bottom

  const scores = history.map((h) => h.score)
  const minS = Math.max(0, Math.min(...scores) - 10)
  const maxS = Math.min(100, Math.max(...scores) + 10)
  const range = maxS - minS || 1

  function xPos(i: number) {
    return PAD.left + (i / (history.length - 1)) * chartW
  }
  function yPos(s: number) {
    return PAD.top + chartH - ((s - minS) / range) * chartH
  }

  const points = history.map((h, i) => `${xPos(i)},${yPos(h.score)}`).join(' ')
  const areaPoints = [
    `${PAD.left},${PAD.top + chartH}`,
    ...history.map((h, i) => `${xPos(i)},${yPos(h.score)}`),
    `${xPos(history.length - 1)},${PAD.top + chartH}`,
  ].join(' ')

  // Label first, last, and middle
  const labelIdxs = new Set([0, Math.floor((history.length - 1) / 2), history.length - 1])
  const firstScore = history[0]!.score
  const lastScore = history[history.length - 1]!.score
  const scoreDelta = lastScore - firstScore

  return (
    <Card variant="default" padding="md">
      <div className="flex items-center justify-between mb-3">
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Score History</p>
        <div className="flex items-center gap-1 text-xs font-medium" style={{ color: scoreDelta >= 0 ? 'hsl(152,65%,48%)' : 'hsl(0,70%,50%)' }}>
          {scoreDelta > 0 && <TrendingUp className="h-3.5 w-3.5" />}
          {scoreDelta < 0 && <TrendingDown className="h-3.5 w-3.5" />}
          {scoreDelta === 0 && <Minus className="h-3.5 w-3.5 text-muted-foreground" />}
          {scoreDelta !== 0 && <span>{scoreDelta > 0 ? '+' : ''}{scoreDelta} pts</span>}
          {scoreDelta === 0 && <span className="text-muted-foreground">Stable</span>}
        </div>
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="xMidYMid meet" className="w-full" style={{ height: 80 }}>
        {/* Grid lines at 25, 50, 75, 100 */}
        {[25, 50, 75, 100].filter((v) => v >= minS && v <= maxS).map((v) => (
          <g key={v}>
            <line x1={PAD.left} y1={yPos(v)} x2={W - PAD.right} y2={yPos(v)} stroke="currentColor" strokeOpacity={0.06} strokeWidth={1} />
            <text x={PAD.left - 3} y={yPos(v) + 3} textAnchor="end" fontSize={6} fill="currentColor" opacity={0.4}>{v}</text>
          </g>
        ))}
        {/* Area fill */}
        <polygon points={areaPoints} fill={color} opacity={0.08} />
        {/* Line */}
        <polyline points={points} fill="none" stroke={color} strokeWidth={1.5} strokeLinejoin="round" strokeLinecap="round" opacity={0.85} />
        {/* Dots + date labels at first/middle/last */}
        {history.map((h, i) => (
          <g key={i}>
            <circle cx={xPos(i)} cy={yPos(h.score)} r={labelIdxs.has(i) ? 2.5 : 1.5} fill={color} opacity={0.9} />
            {labelIdxs.has(i) && (
              <text x={xPos(i)} y={H - 3} textAnchor="middle" fontSize={6.5} fill="currentColor" opacity={0.45}>
                {new Date(h.recorded_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
              </text>
            )}
          </g>
        ))}
      </svg>
      <p className="text-[10px] text-muted-foreground mt-1">{history.length} snapshot{history.length !== 1 ? 's' : ''} recorded</p>
    </Card>
  )
}

function TipCard({
  icon: Icon, color, title, description, href,
}: {
  icon: React.ComponentType<{ className?: string }>
  color: string
  title: string
  description: string
  href: string
}) {
  return (
    <Link href={href}>
      <Card variant="default" hover padding="md">
        <div className="flex items-start gap-3">
          <div
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl"
            style={{ background: `${color}18`, color }}
          >
            <Icon className="h-4 w-4" />
          </div>
          <div>
            <p className="text-sm font-medium text-foreground">{title}</p>
            <p className="text-xs text-muted-foreground mt-0.5">{description}</p>
          </div>
        </div>
      </Card>
    </Link>
  )
}

function getRelativeTime(dateStr: string): string {
  const delta = Date.now() - new Date(dateStr).getTime()
  const minutes = Math.floor(delta / 60000)
  const hours = Math.floor(minutes / 60)
  const days = Math.floor(hours / 24)
  if (minutes < 60) return `${minutes}m ago`
  if (hours < 24) return `${hours}h ago`
  return `${days}d ago`
}
