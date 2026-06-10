'use client'

import * as React from 'react'
import Link from 'next/link'
import { Zap, Flame, Droplets, Sun, Thermometer, Plus, Trash2, Circle } from 'lucide-react'
import type { EnergyReading, MeterType } from '@/lib/supabase/types'
import { createClient } from '@/lib/supabase/client'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'

interface EnergyOverviewProps {
  readings: EnergyReading[]
  ytdUtilities: number
  monthlyUtilities: number
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

export function EnergyOverview({ readings, ytdUtilities, monthlyUtilities, currency, propertyId }: EnergyOverviewProps) {
  const [allReadings, setAllReadings] = React.useState(readings)
  const [deleting, setDeleting] = React.useState<string | null>(null)

  const currencySymbol = currency === 'EUR' ? '€' : currency === 'USD' ? '$' : currency === 'GBP' ? '£' : currency

  // Latest reading per meter type (readings are pre-sorted newest-first by server)
  const latestByType = React.useMemo(() => {
    const map = new Map<MeterType, EnergyReading>()
    for (const r of allReadings) {
      if (!map.has(r.meter_type)) map.set(r.meter_type, r)
    }
    return map
  }, [allReadings])

  const activeMeterTypes = Array.from(latestByType.keys())

  async function handleDelete(id: string) {
    if (!confirm('Delete this reading?')) return
    setDeleting(id)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('energy_readings').delete().eq('id', id)
    setAllReadings((prev) => prev.filter((r) => r.id !== id))
    setDeleting(null)
  }

  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
      {/* Utility cost summary (sourced from Finances module) */}
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
              const date = new Date(reading.reading_date)
              return (
                <Card key={meterType} variant="default" padding="sm">
                  <div className="flex items-center gap-2 mb-2">
                    <div
                      className="flex h-7 w-7 items-center justify-center rounded-lg"
                      style={{ background: `${color}22` }}
                    >
                      <Icon className="h-3.5 w-3.5" style={{ color }} />
                    </div>
                    <span className="text-xs font-medium text-muted-foreground truncate">{label}</span>
                  </div>
                  <p className="text-xl font-bold text-foreground leading-tight">
                    {reading.reading_value.toLocaleString()}
                    <span className="text-sm font-normal text-muted-foreground ml-1">{reading.unit}</span>
                  </p>
                  {reading.cost != null && (
                    <p className="text-xs text-muted-foreground mt-0.5">
                      {reading.cost_currency ?? currency} {reading.cost.toLocaleString()}
                    </p>
                  )}
                  <p className="text-[10px] text-muted-foreground mt-1">
                    {date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
                  </p>
                </Card>
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
