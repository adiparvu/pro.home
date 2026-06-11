'use client'

import * as React from 'react'
import { TrendingUp, TrendingDown, Minus, BarChart2 } from 'lucide-react'
import type { Property, FinanceCategory } from '@/lib/supabase/types'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { cn } from '@/lib/utils'

interface ForecastItem {
  category: string
  avg_monthly: number
  next_month_forecast: number
  trend: 'up' | 'down' | 'stable'
  last3_avg: number
  last6_avg: number
}

interface ForecastResponse {
  forecasts: ForecastItem[]
  total_forecast: number
}

interface ForecastPageProps {
  property: Property
}

const CATEGORY_COLORS: Record<string, string> = {
  maintenance:  'hsl(22,68%,45%)',
  utilities:    'hsl(220,62%,52%)',
  insurance:    'hsl(152,62%,42%)',
  mortgage:     'hsl(270,62%,52%)',
  tax:          'hsl(0,68%,44%)',
  renovation:   'hsl(45,75%,42%)',
  appliance:    'hsl(180,52%,42%)',
  subscription: 'hsl(310,52%,48%)',
  other:        'hsl(0,0%,50%)',
}

function getCategoryColor(cat: string): string {
  return CATEGORY_COLORS[cat as FinanceCategory] ?? 'hsl(220,62%,52%)'
}

function SkeletonRow() {
  return (
    <div className="flex items-center gap-3 py-3 animate-pulse">
      <div className="h-8 w-8 rounded-xl bg-muted/40 shrink-0" />
      <div className="flex-1 flex flex-col gap-1.5">
        <div className="h-3 w-24 rounded bg-muted/40" />
        <div className="h-2.5 w-16 rounded bg-muted/30" />
      </div>
      <div className="h-4 w-16 rounded bg-muted/40" />
    </div>
  )
}

export function ForecastPage({ property }: ForecastPageProps) {
  const [data, setData] = React.useState<ForecastResponse | null>(null)
  const [loading, setLoading] = React.useState(true)
  const [error, setError] = React.useState<string | null>(null)

  React.useEffect(() => {
    let cancelled = false
    async function fetchForecast() {
      try {
        const res = await fetch('/api/finances/forecast')
        if (!res.ok) throw new Error('Failed to load forecast')
        const json = (await res.json()) as ForecastResponse
        if (!cancelled) {
          setData(json)
          setLoading(false)
        }
      } catch (err) {
        if (!cancelled) {
          setError((err as Error).message ?? 'Something went wrong')
          setLoading(false)
        }
      }
    }
    void fetchForecast()
    return () => { cancelled = true }
  }, [])

  const maxForecast = data ? Math.max(...data.forecasts.map((f) => f.next_month_forecast), 1) : 1

  const nextMonthLabel = (() => {
    const d = new Date()
    d.setMonth(d.getMonth() + 1)
    return d.toLocaleString('en-US', { month: 'long', year: 'numeric' })
  })()

  return (
    <>
      <PageHeader title="Forecast" description={property.name} />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6">

        {/* Summary card */}
        <Card variant="default" padding="sm">
          <div className="flex items-center gap-2 mb-1">
            <BarChart2 className="h-4 w-4 text-[hsl(220,62%,60%)]" />
            <p className="text-xs text-muted-foreground">Forecast next month — {nextMonthLabel}</p>
          </div>
          {loading ? (
            <div className="h-7 w-28 rounded bg-muted/40 animate-pulse" />
          ) : error ? (
            <p className="text-sm text-destructive">{error}</p>
          ) : (
            <p className="text-xl font-bold text-[hsl(220,62%,60%)]">
              €{Math.round(data?.total_forecast ?? 0).toLocaleString()}
              <span className="text-sm font-normal text-muted-foreground ml-1">total</span>
            </p>
          )}
        </Card>

        {/* Per-category breakdown */}
        <Card variant="default" padding="md">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
            By category
          </p>

          {loading ? (
            <div className="flex flex-col divide-y divide-border/40">
              {Array.from({ length: 5 }).map((_, i) => <SkeletonRow key={i} />)}
            </div>
          ) : error ? (
            <p className="text-sm text-muted-foreground py-4 text-center">{error}</p>
          ) : !data || data.forecasts.length === 0 ? (
            <div className="flex flex-col items-center gap-2 py-10 text-center">
              <BarChart2 className="h-8 w-8 text-muted-foreground" />
              <p className="text-sm font-medium text-foreground">No data yet</p>
              <p className="text-xs text-muted-foreground max-w-[200px]">
                Add expense records to see spending forecasts
              </p>
            </div>
          ) : (
            <div className="flex flex-col gap-3">
              {data.forecasts.map((item) => {
                const color = getCategoryColor(item.category)
                const barPct = maxForecast > 0 ? (item.next_month_forecast / maxForecast) * 100 : 0

                return (
                  <div key={item.category}>
                    <div className="flex items-center gap-3 mb-1.5">
                      <div
                        className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl"
                        style={{ background: `${color}18`, border: `1px solid ${color}30` }}
                      >
                        <BarChart2 className="h-4 w-4" style={{ color }} />
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center justify-between gap-2">
                          <span className="text-sm font-medium capitalize text-foreground">{item.category}</span>
                          <div className="flex items-center gap-1.5">
                            <TrendIcon trend={item.trend} />
                            <span className="text-sm font-semibold tabular-nums">
                              €{Math.round(item.next_month_forecast).toLocaleString()}
                            </span>
                          </div>
                        </div>
                        <div className="flex items-center justify-between text-[10px] text-muted-foreground mt-0.5">
                          <span>12mo avg: €{Math.round(item.avg_monthly).toLocaleString()}</span>
                          <span>3mo avg: €{Math.round(item.last3_avg).toLocaleString()}</span>
                        </div>
                      </div>
                    </div>
                    {/* Horizontal bar */}
                    <div className="h-1.5 rounded-full overflow-hidden" style={{ background: `${color}14` }}>
                      <div
                        className="h-full rounded-full transition-all duration-700"
                        style={{ width: `${barPct}%`, background: color }}
                      />
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </Card>

        {/* Trend legend */}
        {data && data.forecasts.length > 0 && (
          <div className="flex items-center gap-4 px-1">
            <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <TrendingUp className="h-3.5 w-3.5 text-destructive" />
              <span>Increasing</span>
            </div>
            <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <TrendingDown className="h-3.5 w-3.5 text-[hsl(152,62%,48%)]" />
              <span>Decreasing</span>
            </div>
            <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <Minus className="h-3.5 w-3.5 text-muted-foreground" />
              <span>Stable</span>
            </div>
          </div>
        )}
      </div>
    </>
  )
}

function TrendIcon({ trend }: { trend: 'up' | 'down' | 'stable' }) {
  if (trend === 'up') return <TrendingUp className={cn('h-3.5 w-3.5 text-destructive')} />
  if (trend === 'down') return <TrendingDown className={cn('h-3.5 w-3.5 text-[hsl(152,62%,48%)]')} />
  return <Minus className={cn('h-3.5 w-3.5 text-muted-foreground')} />
}
