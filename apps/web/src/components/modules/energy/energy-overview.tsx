'use client'

import * as React from 'react'
import Link from 'next/link'
import { Zap, Flame, Droplets, Sun, Thermometer, Plus, Trash2, Circle, TrendingUp, TrendingDown, Minus } from 'lucide-react'
import type { EnergyReading, MeterType } from '@/lib/supabase/types'
import { createClient } from '@/lib/supabase/client'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'

interface EnergyOverviewProps {
  readings: EnergyReading[]
  ytdUtilities: number
  monthlyUtilities: number
  utilityBudget: number
  currency: string
  propertyId: string
}

const METER_CONFIG: Record<MeterType, {
  label: string
  icon: React.ComponentType<{ className?: string; style?: React.CSSProperties }>
  color: string
}> = {
  electricity:      { label: 'Electricity',   icon: Zap,         color: 'hsl(45, 75%, 50%)' },
  gas:              { label: 'Gas',            icon: Flame,       color: 'hsl(22, 68%, 52%)' },
  water:            { label: 'Water',          icon: Droplets,    color: 'hsl(210, 70%, 52%)' },
  solar:            { label: 'Solar',          icon: Sun,         color: 'hsl(50, 90%, 50%)' },
  district_heating: { label: 'District Heat', icon: Thermometer, color: 'hsl(0, 62%, 52%)' },
  other:            { label: 'Other',          icon: Circle,      color: 'hsl(0, 0%, 52%)' },
}

// Derive consumption deltas between consecutive readings of the same meter
function consumptionDeltas(readings: EnergyReading[], meterType: MeterType) {
  const sorted = readings
    .filter((r) => r.meter_type === meterType)
    .sort((a, b) => a.reading_date.localeCompare(b.reading_date))
  if (sorted.length < 2) return []
  return sorted.slice(1).map((r, i) => ({
    date: r.reading_date,
    delta: Math.max(0, r.reading_value - sorted[i]!.reading_value),
    unit: r.unit,
  }))
}

export function EnergyOverview({ readings, ytdUtilities, monthlyUtilities, utilityBudget, currency, propertyId }: EnergyOverviewProps) {
  const confirmDialog = useConfirm()
  const [allReadings, setAllReadings] = React.useState(readings)
  const [deleting, setDeleting] = React.useState<string | null>(null)
  const [chartMeter, setChartMeter] = React.useState<MeterType | null>(null)

  const currencySymbol = currency === 'EUR' ? '€' : currency === 'USD' ? '$' : currency === 'GBP' ? '£' : currency

  const latestByType = React.useMemo(() => {
    const map = new Map<MeterType, EnergyReading>()
    for (const r of allReadings) {
      if (!map.has(r.meter_type)) map.set(r.meter_type, r)
    }
    return map
  }, [allReadings])

  const activeMeterTypes = Array.from(latestByType.keys())

  // Set default chart meter on first render
  React.useEffect(() => {
    if (activeMeterTypes.length > 0 && !chartMeter) {
      setChartMeter(activeMeterTypes[0] ?? null)
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeMeterTypes.length])

  async function handleDelete(id: string) {
    const ok = await confirmDialog({
      title: 'Delete this reading?',
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeleting(id)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('energy_readings').delete().eq('id', id)
    toast.success('Reading deleted')
    setAllReadings((prev) => prev.filter((r) => r.id !== id))
    setDeleting(null)
  }

  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[88px] md:pb-6">
      {/* Utility cost summary */}
      <div className="glass-standard rounded-2xl p-5">
        <p className="text-xs text-muted-foreground uppercase tracking-wider mb-3">Utility Costs</p>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <p className="text-xs text-muted-foreground">This month</p>
            <p className="text-xl font-bold text-foreground mt-0.5">
              {currencySymbol}{monthlyUtilities.toLocaleString()}
            </p>
            <p className="text-[10px] text-muted-foreground">from Finances</p>
          </div>
          <div>
            <p className="text-xs text-muted-foreground">Year to date</p>
            <p className="text-xl font-bold text-foreground mt-0.5">
              {currencySymbol}{ytdUtilities.toLocaleString()}
            </p>
            <p className="text-[10px] text-muted-foreground">{new Date().getFullYear()}</p>
          </div>
        </div>
        {utilityBudget > 0 && monthlyUtilities > 0 && (() => {
          const pct = Math.min((monthlyUtilities / utilityBudget) * 100, 110)
          const rawPct = (monthlyUtilities / utilityBudget) * 100
          const isOver = rawPct > 100
          const isWarn = rawPct > 80
          const barColor = isOver ? 'hsl(0,68%,52%)' : isWarn ? 'hsl(45,75%,52%)' : 'hsl(152,62%,42%)'
          return (
            <div className="mt-3 pt-3 border-t border-white/10">
              <div className="flex items-center justify-between mb-1.5">
                <span className="text-xs text-muted-foreground">Monthly budget</span>
                <span className={`text-xs font-bold tabular-nums ${isOver ? 'text-destructive' : isWarn ? 'text-[hsl(45,75%,52%)]' : 'text-[hsl(152,62%,48%)]'}`}>
                  {Math.round(rawPct)}% · {currencySymbol}{utilityBudget.toLocaleString()}
                </span>
              </div>
              <div className="h-2 rounded-full overflow-hidden bg-white/10">
                <div
                  className="h-full rounded-full transition-all duration-slow"
                  style={{ width: `${pct}%`, background: barColor }}
                />
              </div>
              {isOver && (
                <p className="text-[10px] text-destructive mt-1">
                  Over budget by {currencySymbol}{(monthlyUtilities - utilityBudget).toLocaleString()}
                </p>
              )}
            </div>
          )
        })()}
        {ytdUtilities === 0 && (
          <p className="text-xs text-muted-foreground mt-3 pt-3 border-t border-white/10">
            Log utility expenses in{' '}
            <a href="/finances" className="underline hover:text-foreground">Finances</a>
            {' '}to track costs here.
          </p>
        )}
      </div>

      {/* Per-meter latest reading cards */}
      {activeMeterTypes.length > 0 ? (
        <div className="flex flex-col gap-3">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Meters</p>
          <div className="grid grid-cols-2 gap-3">
            {activeMeterTypes.map((meterType) => {
              const reading = latestByType.get(meterType)!
              const { label, icon: Icon, color } = METER_CONFIG[meterType]
              const meterReadings = allReadings.filter((r) => r.meter_type === meterType)
              const sorted = [...meterReadings].sort((a, b) => a.reading_date.localeCompare(b.reading_date))
              const prev = sorted.at(-2)
              const latest = sorted.at(-1)
              const delta = prev && latest ? latest.reading_value - prev.reading_value : null
              const trend = delta == null ? null : delta > 0 ? 'up' : delta < 0 ? 'down' : 'flat'

              return (
                <button
                  key={meterType}
                  type="button"
                  onClick={() => setChartMeter(meterType)}
                  className={cn(
                    'text-left transition-all rounded-2xl',
                    chartMeter === meterType ? 'ring-2' : ''
                  )}
                  style={chartMeter === meterType ? { '--tw-ring-color': color } as React.CSSProperties : undefined}
                >
                  <Card variant="default" padding="sm" className="h-full">
                    <div className="flex items-center justify-between mb-2">
                      <div
                        className="flex h-7 w-7 items-center justify-center rounded-lg"
                        style={{ background: `${color}22` }}
                      >
                        <Icon className="h-3.5 w-3.5" style={{ color }} />
                      </div>
                      {trend && (
                        <span className="text-[10px] text-muted-foreground">
                          {trend === 'up' && <TrendingUp className="h-3 w-3 text-destructive" />}
                          {trend === 'down' && <TrendingDown className="h-3 w-3 text-[hsl(152,62%,48%)]" />}
                          {trend === 'flat' && <Minus className="h-3 w-3" />}
                        </span>
                      )}
                    </div>
                    {/* Sparkline */}
                    {sorted.length >= 2 && (
                      <SparkLine readings={sorted} color={color} />
                    )}
                    <p className="text-lg font-bold text-foreground leading-tight mt-1">
                      {reading.reading_value.toLocaleString()}
                      <span className="text-xs font-normal text-muted-foreground ml-1">{reading.unit}</span>
                    </p>
                    <p className="text-[10px] text-muted-foreground truncate">{label}</p>
                    {delta != null && delta !== 0 && (
                      <p className="text-[10px] mt-0.5" style={{ color: delta > 0 ? 'hsl(0,68%,52%)' : 'hsl(152,62%,48%)' }}>
                        {delta > 0 ? '+' : ''}{delta.toLocaleString()} since last
                      </p>
                    )}
                  </Card>
                </button>
              )
            })}
          </div>
        </div>
      ) : (
        <div className="flex flex-col items-center gap-3 py-10 text-center rounded-2xl border border-border/50 glass-light">
          <div className="flex h-14 w-14 items-center justify-center rounded-2xl glass-standard">
            <Zap className="h-7 w-7 text-muted-foreground" />
          </div>
          <p className="text-sm font-semibold text-foreground">No readings yet</p>
          <p className="text-xs text-muted-foreground max-w-[220px]">
            Log meter readings to track electricity, gas, water, and solar consumption
          </p>
          <Link href="/energy/new">
            <Button variant="secondary" size="sm">
              <Plus className="h-3.5 w-3.5" />
              Log first reading
            </Button>
          </Link>
        </div>
      )}

      {/* Trend chart */}
      {chartMeter && allReadings.filter((r) => r.meter_type === chartMeter).length >= 2 && (
        <Card variant="default" padding="md">
          <div className="flex items-center justify-between mb-3">
            <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              {METER_CONFIG[chartMeter].label} Trend
            </p>
            {activeMeterTypes.length > 1 && (
              <div className="flex gap-1">
                {activeMeterTypes.map((mt) => {
                  const { icon: Icon, color } = METER_CONFIG[mt]
                  return (
                    <button
                      key={mt}
                      type="button"
                      onClick={() => setChartMeter(mt)}
                      className={cn(
                        'flex h-6 w-6 items-center justify-center rounded-md transition-colors',
                        chartMeter === mt ? 'glass-standard' : 'text-muted-foreground hover:text-foreground'
                      )}
                      style={chartMeter === mt ? { color } : undefined}
                    >
                      <Icon className="h-3.5 w-3.5" />
                    </button>
                  )
                })}
              </div>
            )}
          </div>
          <TrendChart
            readings={allReadings.filter((r) => r.meter_type === chartMeter)}
            color={METER_CONFIG[chartMeter].color}
          />
          {/* Consumption deltas */}
          <ConsumptionSummary deltas={consumptionDeltas(allReadings, chartMeter)} />
        </Card>
      )}

      {/* Reading history */}
      {allReadings.length > 0 && (
        <div className="flex flex-col gap-3">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            Reading History
          </p>
          <div className="flex flex-col gap-2">
            {allReadings.slice(0, 30).map((reading) => {
              const { label, icon: Icon, color } = METER_CONFIG[reading.meter_type]
              const date = new Date(reading.reading_date)
              return (
                <Card key={reading.id} variant="default" padding="md">
                  <div className="flex items-center gap-3">
                    <div
                      className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl"
                      style={{ background: `${color}18` }}
                    >
                      <Icon className="h-4 w-4" style={{ color }} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <p className="text-sm font-medium text-foreground">
                          {reading.reading_value.toLocaleString()} {reading.unit}
                        </p>
                        <Badge variant="neutral" size="xs" className="shrink-0">
                          {label}
                        </Badge>
                      </div>
                      <div className="flex items-center gap-1.5 mt-0.5 flex-wrap">
                        <p className="text-xs text-muted-foreground">
                          {date.toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' })}
                        </p>
                        {reading.cost != null && (
                          <span className="text-xs text-muted-foreground">
                            · {reading.cost_currency ?? currency} {reading.cost.toLocaleString()}
                          </span>
                        )}
                        {reading.provider && (
                          <span className="text-xs text-muted-foreground truncate">· {reading.provider}</span>
                        )}
                        {reading.meter_id && (
                          <span className="text-xs text-muted-foreground/50">#{reading.meter_id}</span>
                        )}
                      </div>
                      {reading.notes && (
                        <p className="text-xs text-muted-foreground italic mt-0.5 truncate">{reading.notes}</p>
                      )}
                    </div>
                    <button
                      type="button"
                      onClick={() => handleDelete(reading.id)}
                      disabled={deleting === reading.id}
                      className="shrink-0 text-muted-foreground hover:text-destructive transition-colors disabled:opacity-40"
                      aria-label="Delete reading"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </div>
                </Card>
              )
            })}
          </div>
        </div>
      )}
    </div>
  )
}

// ─── Sparkline ────────────────────────────────────────────────────────────────

function SparkLine({ readings, color }: { readings: EnergyReading[]; color: string }) {
  if (readings.length < 2) return null
  const values = readings.map((r) => r.reading_value)
  const min = Math.min(...values)
  const max = Math.max(...values)
  const range = max - min || 1

  const W = 100
  const H = 24
  const pts = readings.map((r, i) => {
    const x = (i / (readings.length - 1)) * W
    const y = H - ((r.reading_value - min) / range) * (H - 2) - 1
    return [x, y] as [number, number]
  })

  const linePath = pts.map(([x, y], i) => `${i === 0 ? 'M' : 'L'} ${x} ${y}`).join(' ')
  const areaPath = `${linePath} L ${W} ${H} L 0 ${H} Z`

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full mb-1" preserveAspectRatio="none" style={{ height: 24 }}>
      <path d={areaPath} fill={color} fillOpacity={0.15} />
      <path d={linePath} stroke={color} strokeWidth={1.5} fill="none" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

// ─── Trend chart ──────────────────────────────────────────────────────────────

function TrendChart({ readings, color }: { readings: EnergyReading[]; color: string }) {
  const sorted = [...readings]
    .sort((a, b) => a.reading_date.localeCompare(b.reading_date))
    .slice(-20)

  if (sorted.length < 2) return (
    <p className="text-xs text-muted-foreground text-center py-6">Not enough data for chart</p>
  )

  const PAD = { top: 12, right: 8, bottom: 28, left: 44 }
  const W = 300
  const H = 140
  const cW = W - PAD.left - PAD.right
  const cH = H - PAD.top - PAD.bottom

  const values = sorted.map((r) => r.reading_value)
  const min = Math.min(...values)
  const max = Math.max(...values)
  const range = max - min || 1

  const pts = sorted.map((r, i) => ({
    x: PAD.left + (i / (sorted.length - 1)) * cW,
    y: PAD.top + (1 - (r.reading_value - min) / range) * cH,
    r,
  }))

  const linePath = pts.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(' ')
  const areaPath = `${linePath} L ${(PAD.left + cW).toFixed(1)} ${(PAD.top + cH).toFixed(1)} L ${PAD.left.toFixed(1)} ${(PAD.top + cH).toFixed(1)} Z`

  // Y-axis grid lines (4 steps)
  const steps = 4
  const gridLines = Array.from({ length: steps + 1 }, (_, i) => {
    const v = min + (range * i) / steps
    const y = PAD.top + (1 - (v - min) / range) * cH
    return { v, y }
  })

  // X-axis labels: first, last, and up to 2 middle ones
  const labelIndices = new Set([0, sorted.length - 1])
  if (sorted.length > 4) {
    labelIndices.add(Math.floor(sorted.length / 3))
    labelIndices.add(Math.floor((2 * sorted.length) / 3))
  }

  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      className="w-full"
      style={{ aspectRatio: `${W}/${H}` }}
      role="img"
      aria-label="Energy reading trend chart"
    >
      {/* Grid lines */}
      {gridLines.map(({ v, y }, i) => (
        <g key={i}>
          <line
            x1={PAD.left} y1={y.toFixed(1)}
            x2={PAD.left + cW} y2={y.toFixed(1)}
            stroke="currentColor" strokeOpacity={0.08} strokeWidth={1}
          />
          <text
            x={PAD.left - 4} y={(y + 3.5).toFixed(1)}
            textAnchor="end" fontSize={8}
            fill="currentColor" fillOpacity={0.45}
          >
            {v >= 1000 ? `${(v / 1000).toFixed(1)}k` : v.toFixed(0)}
          </text>
        </g>
      ))}

      {/* Area fill */}
      <path d={areaPath} fill={color} fillOpacity={0.12} />
      {/* Line */}
      <path d={linePath} stroke={color} strokeWidth={2} fill="none" strokeLinecap="round" strokeLinejoin="round" />
      {/* Dots */}
      {pts.map((p, i) => (
        <circle key={i} cx={p.x.toFixed(1)} cy={p.y.toFixed(1)} r={2.5} fill={color} />
      ))}

      {/* X-axis labels */}
      {pts.map((p, i) =>
        labelIndices.has(i) ? (
          <text
            key={i}
            x={p.x.toFixed(1)}
            y={(H - 4).toFixed(1)}
            textAnchor={i === 0 ? 'start' : i === sorted.length - 1 ? 'end' : 'middle'}
            fontSize={8}
            fill="currentColor"
            fillOpacity={0.4}
          >
            {new Date(p.r.reading_date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
          </text>
        ) : null
      )}
    </svg>
  )
}

// ─── Consumption summary ──────────────────────────────────────────────────────

function ConsumptionSummary({
  deltas,
}: {
  deltas: { date: string; delta: number; unit: string }[]
}) {
  if (deltas.length === 0) return null
  const last3 = deltas.slice(-3).reverse()
  const avg = deltas.reduce((s, d) => s + d.delta, 0) / deltas.length

  return (
    <div className="mt-3 pt-3 border-t border-border/30 flex gap-4">
      <div>
        <p className="text-[10px] text-muted-foreground uppercase tracking-wider">Avg delta</p>
        <p className="text-sm font-semibold text-foreground">
          {avg.toLocaleString(undefined, { maximumFractionDigits: 1 })}
          <span className="text-xs font-normal text-muted-foreground ml-1">{deltas[0]?.unit}</span>
        </p>
      </div>
      <div className="flex-1">
        <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1">Recent deltas</p>
        <div className="flex gap-1.5">
          {last3.map((d, i) => (
            <span key={i} className="rounded-full glass-light px-2 py-0.5 text-[10px] text-muted-foreground whitespace-nowrap">
              +{d.delta.toLocaleString(undefined, { maximumFractionDigits: 1 })}
            </span>
          ))}
        </div>
      </div>
    </div>
  )
}
