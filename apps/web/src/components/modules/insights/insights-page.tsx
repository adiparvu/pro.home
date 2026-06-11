'use client'

import * as React from 'react'
import {
  TrendingUp, TrendingDown, Wrench, Zap, AlertTriangle, Sparkles,
  RefreshCw, ChevronDown, ChevronUp, DollarSign, Calendar, FileText,
  BarChart3, Activity,
} from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { PageHeader } from '@/components/layout/page-header'
import { cn } from '@/lib/utils'
import type { InsightsData } from '@/app/(app)/insights/page'

interface InsightsPageProps {
  data: InsightsData
  propertyName: string
}

function StatCard({ icon: Icon, label, value, sub, color }: {
  icon: React.ElementType
  label: string
  value: string
  sub?: string
  color: string
}) {
  return (
    <Card variant="default" padding="sm">
      <div className="flex items-start gap-2">
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl" style={{ background: `${color}22` }}>
          <Icon className="h-4 w-4" style={{ color }} />
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-xs text-muted-foreground truncate">{label}</p>
          <p className="text-base font-bold text-foreground">{value}</p>
          {sub && <p className="text-[10px] text-muted-foreground">{sub}</p>}
        </div>
      </div>
    </Card>
  )
}

function ProgressBar({ value, max, color }: { value: number; max: number; color: string }) {
  const pct = max > 0 ? Math.min(100, (value / max) * 100) : 0
  return (
    <div className="h-1.5 w-full rounded-full bg-border overflow-hidden">
      <div className="h-full rounded-full transition-all duration-slow" style={{ width: `${pct}%`, background: color }} />
    </div>
  )
}

function AiBrief({ brief, loading, onRefresh }: {
  brief: string | null
  loading: boolean
  onRefresh: () => void
}) {
  const lines = brief?.split('\n').filter(Boolean) ?? []

  return (
    <Card variant="heavy" padding="md">
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          <Sparkles className="h-4 w-4 text-[hsl(280,68%,60%)]" />
          <p className="text-sm font-semibold text-foreground">Property Brief</p>
        </div>
        <button
          onClick={onRefresh}
          disabled={loading}
          className="flex items-center gap-1.5 rounded-lg px-2.5 py-1 text-xs text-muted-foreground hover:text-foreground transition-colors focus-ring"
        >
          <RefreshCw className={cn('h-3 w-3', loading && 'animate-spin')} />
          {loading ? 'Generating…' : 'Refresh'}
        </button>
      </div>

      {loading && (
        <div className="space-y-2">
          {[80, 60, 90, 50, 70].map((w, i) => (
            <div key={i} className="h-3 rounded animate-pulse bg-border" style={{ width: `${w}%` }} />
          ))}
        </div>
      )}

      {!loading && !brief && (
        <div className="flex flex-col items-center gap-3 py-4 text-center">
          <Sparkles className="h-8 w-8 text-[hsl(280,68%,60%)]/50" />
          <p className="text-sm text-muted-foreground">Generate your first property intelligence brief</p>
          <Button variant="secondary" size="sm" onClick={onRefresh}>Generate Brief</Button>
        </div>
      )}

      {!loading && brief && (
        <div className="prose prose-sm dark:prose-invert max-w-none text-sm text-foreground/90 leading-relaxed">
          {lines.map((line, i) => {
            if (line.startsWith('**') && line.endsWith('**')) {
              return <p key={i} className="font-semibold text-foreground mt-3 first:mt-0">{line.slice(2, -2)}</p>
            }
            if (line.startsWith('• ') || line.startsWith('- ')) {
              return <p key={i} className="pl-3 text-foreground/80">• {line.slice(2)}</p>
            }
            // Handle inline bold: **text**
            const parts = line.split(/(\*\*[^*]+\*\*)/)
            return (
              <p key={i} className="text-foreground/80">
                {parts.map((p, j) =>
                  p.startsWith('**') ? <strong key={j}>{p.slice(2, -2)}</strong> : p
                )}
              </p>
            )
          })}
        </div>
      )}
    </Card>
  )
}

export function InsightsPage({ data, propertyName }: InsightsPageProps) {
  const [brief, setBrief] = React.useState<string | null>(null)
  const [briefLoading, setBriefLoading] = React.useState(false)
  const [expandedCategory, setExpandedCategory] = React.useState<string | null>(null)

  async function fetchBrief() {
    setBriefLoading(true)
    try {
      const res = await fetch('/api/insights', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: 'full' }),
      })
      const json = await res.json() as { brief?: string; error?: string }
      if (json.brief) setBrief(json.brief)
    } finally {
      setBriefLoading(false)
    }
  }

  const { stats, topCategories, tasksByStatus, monthlyTrend, warrantyAlerts } = data

  const balance = stats.ytdIncome - stats.ytdExpenses
  const maxCategory = topCategories.reduce((m, c) => Math.max(m, c.total), 0)

  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6">
      <PageHeader title="Insights" description={propertyName} />

      {/* KPI strip */}
      <div className="grid grid-cols-2 gap-3">
        <StatCard
          icon={TrendingDown}
          label="YTD Expenses"
          value={`€${stats.ytdExpenses.toLocaleString()}`}
          sub={`${stats.expenseCount} transactions`}
          color="hsl(0,68%,44%)"
        />
        <StatCard
          icon={balance >= 0 ? TrendingUp : TrendingDown}
          label="Net Balance"
          value={`${balance >= 0 ? '+' : ''}€${Math.abs(balance).toLocaleString()}`}
          color={balance >= 0 ? 'hsl(152,62%,42%)' : 'hsl(0,68%,44%)'}
        />
        <StatCard
          icon={Wrench}
          label="Open Tasks"
          value={String(stats.openTasks)}
          sub={stats.overdueTasks > 0 ? `${stats.overdueTasks} overdue` : 'all on track'}
          color={stats.overdueTasks > 0 ? 'hsl(0,68%,44%)' : 'hsl(22,68%,41%)'}
        />
        <StatCard
          icon={DollarSign}
          label="Avg Monthly"
          value={`€${stats.avgMonthlyExpense.toLocaleString()}`}
          sub="this year"
          color="hsl(45,75%,42%)"
        />
      </div>

      {/* AI Brief */}
      <AiBrief brief={brief} loading={briefLoading} onRefresh={fetchBrief} />

      {/* Task breakdown */}
      <Card variant="default" padding="md">
        <p className="text-sm font-semibold text-foreground mb-3">Task Status</p>
        <div className="flex gap-2 flex-wrap">
          {tasksByStatus.map(({ status, count, color }) => (
            <div key={status} className="flex items-center gap-1.5 rounded-full px-2.5 py-1 glass-light">
              <div className="h-2 w-2 rounded-full" style={{ background: color }} />
              <span className="text-xs text-foreground capitalize">{status.replace('_', ' ')}</span>
              <Badge variant="neutral" className="text-[10px] py-0 h-4">{count}</Badge>
            </div>
          ))}
        </div>
      </Card>

      {/* Spending by category */}
      <Card variant="default" padding="md">
        <p className="text-sm font-semibold text-foreground mb-3">Spending by Category</p>
        <div className="flex flex-col gap-3">
          {topCategories.slice(0, 6).map(({ category, total, count }) => (
            <div key={category}>
              <button
                type="button"
                onClick={() => setExpandedCategory(expandedCategory === category ? null : category)}
                className="flex items-center gap-2 w-full text-left"
              >
                <span className="text-xs capitalize text-foreground w-24 truncate">{category}</span>
                <div className="flex-1">
                  <ProgressBar value={total} max={maxCategory} color="hsl(210,75%,42%)" />
                </div>
                <span className="text-xs font-medium text-foreground w-16 text-right">€{total.toLocaleString()}</span>
                {expandedCategory === category ? <ChevronUp className="h-3 w-3 text-muted-foreground" /> : <ChevronDown className="h-3 w-3 text-muted-foreground" />}
              </button>
              {expandedCategory === category && (
                <p className="text-xs text-muted-foreground mt-1 pl-26">{count} transaction{count !== 1 ? 's' : ''}</p>
              )}
            </div>
          ))}
        </div>
      </Card>

      {/* Monthly trend */}
      {monthlyTrend.length > 0 && (
        <Card variant="default" padding="md">
          <p className="text-sm font-semibold text-foreground mb-3">Monthly Expenses (last 6 months)</p>
          <div className="flex items-end gap-1.5 h-24">
            {monthlyTrend.map(({ month, total }) => {
              const maxVal = Math.max(...monthlyTrend.map((m) => m.total), 1)
              const h = Math.max(4, (total / maxVal) * 96)
              return (
                <div key={month} className="flex-1 flex flex-col items-center gap-1">
                  <div
                    className="w-full rounded-t-md transition-all duration-slow"
                    style={{ height: `${h}px`, background: 'hsl(210,75%,42%)' }}
                    title={`€${total.toLocaleString()}`}
                  />
                  <span className="text-[9px] text-muted-foreground">{month}</span>
                </div>
              )
            })}
          </div>
        </Card>
      )}

      {/* Warranty alerts */}
      {warrantyAlerts.length > 0 && (
        <Card variant="default" padding="md">
          <div className="flex items-center gap-2 mb-3">
            <AlertTriangle className="h-4 w-4 text-[hsl(45,75%,42%)]" />
            <p className="text-sm font-semibold text-foreground">Expiring Warranties</p>
          </div>
          <div className="flex flex-col gap-2">
            {warrantyAlerts.map(({ name, expiresAt, daysLeft }) => (
              <div key={name} className="flex items-center justify-between">
                <p className="text-sm text-foreground truncate">{name}</p>
                <Badge variant={daysLeft < 30 ? 'warning' : 'neutral'} className="shrink-0 ml-2">
                  {daysLeft}d left
                </Badge>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Calendar export link */}
      <a
        href="/api/calendar/maintenance"
        className="flex items-center gap-2 rounded-xl glass-light px-4 py-3 text-sm text-muted-foreground hover:text-foreground transition-colors"
      >
        <Calendar className="h-4 w-4" />
        Subscribe to maintenance calendar (.ics)
      </a>

      {/* Full calendar export */}
      <a
        href="/api/calendar/export"
        download
        className="flex items-center gap-2 rounded-xl glass-light px-4 py-3 text-sm text-muted-foreground hover:text-foreground transition-colors"
      >
        <Calendar className="h-4 w-4" />
        Export to calendar (all events) →
      </a>

      {/* Energy link */}
      <a
        href="/energy"
        className="flex items-center gap-2 rounded-xl glass-light px-4 py-3 text-sm text-muted-foreground hover:text-foreground transition-colors"
      >
        <Zap className="h-4 w-4" />
        View detailed energy readings →
      </a>

      {/* Property value tracker link */}
      <a
        href="/property/value"
        className="flex items-center gap-2 rounded-xl glass-light px-4 py-3 text-sm text-muted-foreground hover:text-foreground transition-colors"
      >
        <TrendingUp className="h-4 w-4" />
        Track property value over time →
      </a>

      {/* PDF Report */}
      <a
        href="/api/reports/property"
        target="_blank"
        rel="noopener noreferrer"
        className="flex items-center gap-2 rounded-xl glass-light px-4 py-3 text-sm text-muted-foreground hover:text-foreground transition-colors"
      >
        <FileText className="h-4 w-4" />
        Download full property report →
      </a>

      {/* Predictive maintenance hint */}
      {data.stats.overdueTasks > 0 && (
        <Card variant="default" padding="md">
          <div className="flex items-center gap-2 mb-2">
            <Activity className="h-4 w-4 text-[hsl(22,68%,45%)]" />
            <p className="text-sm font-semibold">Maintenance Health</p>
          </div>
          <div className="flex items-center gap-3">
            <div className="flex-1">
              <div className="flex justify-between text-xs text-muted-foreground mb-1">
                <span>Task completion rate</span>
                <span>{data.stats.openTasks > 0 ? Math.round((1 - data.stats.overdueTasks / (data.stats.openTasks + data.stats.overdueTasks)) * 100) : 100}%</span>
              </div>
              <ProgressBar
                value={data.stats.openTasks}
                max={data.stats.openTasks + data.stats.overdueTasks}
                color="hsl(152,62%,42%)"
              />
            </div>
          </div>
          {data.stats.overdueTasks > 0 && (
            <p className="text-xs text-muted-foreground mt-2">
              ⚠ {data.stats.overdueTasks} overdue task{data.stats.overdueTasks > 1 ? 's' : ''} — address these to improve your property health score
            </p>
          )}
        </Card>
      )}
    </div>
  )
}
