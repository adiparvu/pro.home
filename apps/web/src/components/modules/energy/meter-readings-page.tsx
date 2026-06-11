'use client'

import * as React from 'react'
import {
  Zap, Flame, Droplets, Thermometer, Plus, X, Loader2, Trash2, Sun,
} from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import type { Property } from '@/lib/supabase/types'

type MeterType = 'electricity' | 'gas' | 'water' | 'hot_water' | 'solar' | 'other'

interface MeterReading {
  id: string
  property_id: string
  meter_type: MeterType
  meter_id: string | null
  reading: number
  unit: string | null
  reading_date: string
  photo_url: string | null
  notes: string | null
  logged_by: string | null
  created_at: string
}

interface MeterReadingsPageProps {
  property: Property
  userId: string
  initialReadings: MeterReading[]
}

const METER_TYPES: MeterType[] = ['electricity', 'gas', 'water', 'hot_water', 'solar', 'other']

const METER_CONFIG: Record<MeterType, {
  label: string
  icon: React.ComponentType<{ className?: string }>
  color: string
  defaultUnit: string
}> = {
  electricity: { label: 'Electricity', icon: Zap,         color: 'hsl(45,75%,42%)',   defaultUnit: 'kWh' },
  gas:         { label: 'Gas',         icon: Flame,        color: 'hsl(22,68%,45%)',   defaultUnit: 'm³'  },
  water:       { label: 'Water',       icon: Droplets,     color: 'hsl(210,75%,42%)',  defaultUnit: 'm³'  },
  hot_water:   { label: 'Hot Water',   icon: Thermometer,  color: 'hsl(0,68%,44%)',    defaultUnit: 'm³'  },
  solar:       { label: 'Solar',       icon: Sun,          color: 'hsl(88,58%,39%)',   defaultUnit: 'kWh' },
  other:       { label: 'Other',       icon: Zap,          color: 'hsl(220,52%,46%)',  defaultUnit: ''    },
}

function today() {
  return new Date().toISOString().slice(0, 10)
}

function formatDate(d: string) {
  return new Date(d + 'T00:00:00').toLocaleDateString('en', { day: 'numeric', month: 'short', year: 'numeric' })
}

// Benchmarking reference values
interface BenchmarkRange {
  excellent: number
  good: number
  average: number
  unit: string
  label: string
  meterType: MeterType
}

const BENCHMARKS: BenchmarkRange[] = [
  { meterType: 'electricity', label: 'Electricity', unit: 'kWh/m²/year', excellent: 50, good: 100, average: 150 },
  { meterType: 'gas', label: 'Gas', unit: 'm³/year', excellent: 500, good: 1000, average: 1500 },
  { meterType: 'water', label: 'Water', unit: 'm³/year', excellent: 80, good: 120, average: 180 },
]

function getBenchmarkLabel(value: number, b: BenchmarkRange): { grade: string; color: string; pct: number } {
  const mid = b.good
  const pct = Math.round(((value - mid) / mid) * 100)
  if (value < b.excellent) return { grade: 'Excellent', color: 'hsl(152,62%,38%)', pct }
  if (value < b.good) return { grade: 'Good', color: 'hsl(88,58%,39%)', pct }
  if (value < b.average) return { grade: 'Average', color: 'hsl(45,75%,42%)', pct }
  return { grade: 'Poor', color: 'hsl(0,68%,44%)', pct }
}

export function MeterReadingsPage({ property, userId, initialReadings }: MeterReadingsPageProps) {
  const confirmDialog = useConfirm()
  const [readings, setReadings] = React.useState<MeterReading[]>(initialReadings)
  const [typeFilter, setTypeFilter] = React.useState<MeterType | 'all'>('all')
  const [showForm, setShowForm] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)

  // Form state
  const [meterType, setMeterType] = React.useState<MeterType>('electricity')
  const [meterId, setMeterId] = React.useState('')
  const [readingVal, setReadingVal] = React.useState('')
  const [unit, setUnit] = React.useState('kWh')
  const [readingDate, setReadingDate] = React.useState(today())
  const [notes, setNotes] = React.useState('')

  React.useEffect(() => {
    setUnit(METER_CONFIG[meterType].defaultUnit)
  }, [meterType])

  const filtered = typeFilter === 'all' ? readings : readings.filter((r) => r.meter_type === typeFilter)

  // Latest reading per type
  const latestByType = React.useMemo(() => {
    const map: Partial<Record<MeterType, MeterReading>> = {}
    for (const r of readings) {
      if (!map[r.meter_type]) map[r.meter_type] = r
    }
    return map
  }, [readings])

  // Last 6 readings for selected type (for bar chart)
  const chartReadings = React.useMemo(() => {
    const src = typeFilter === 'all' ? readings : readings.filter((r) => r.meter_type === typeFilter)
    return src.slice(0, 6).reverse()
  }, [readings, typeFilter])

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    if (!readingVal) return
    setSaving(true)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('meter_readings')
        .insert({
          property_id: property.id,
          meter_type: meterType,
          meter_id: meterId.trim() || null,
          reading: parseFloat(readingVal),
          unit: unit.trim() || null,
          reading_date: readingDate,
          notes: notes.trim() || null,
          logged_by: userId,
        })
        .select()
        .single()
      if (error) throw error
      setReadings((prev) => [data, ...prev])
      setReadingVal(''); setMeterId(''); setNotes('')
      setShowForm(false)
      toast({ title: 'Reading logged' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete(r: MeterReading) {
    const ok = await confirmDialog({
      title: 'Delete reading',
      description: 'Remove this meter reading?',
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(r.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('meter_readings').delete().eq('id', r.id)
      setReadings((prev) => prev.filter((x) => x.id !== r.id))
    } finally {
      setDeletingId(null)
    }
  }

  const maxReading = Math.max(...chartReadings.map((r) => r.reading), 1)

  return (
    <>
      <PageHeader
        title="Meter Readings"
        description={property.name}
        action={{ label: 'Log Reading', href: '#', onClick: () => setShowForm(true) }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Type filter */}
        <div className="flex gap-2 flex-wrap">
          <button
            onClick={() => setTypeFilter('all')}
            className={cn('px-3 py-1 rounded-full text-xs font-medium border transition-colors', typeFilter === 'all' ? 'bg-primary text-white border-primary' : 'border-border/50 text-muted-foreground hover:text-foreground')}
          >
            All
          </button>
          {METER_TYPES.map((t) => (
            <button
              key={t}
              onClick={() => setTypeFilter(t)}
              className={cn('px-3 py-1 rounded-full text-xs font-medium border transition-colors', typeFilter === t ? 'bg-primary text-white border-primary' : 'border-border/50 text-muted-foreground hover:text-foreground')}
            >
              {METER_CONFIG[t].label}
            </button>
          ))}
        </div>

        {/* Summary cards */}
        <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
          {METER_TYPES.filter((t) => latestByType[t]).map((t) => {
            const cfg = METER_CONFIG[t]
            const TypeIcon = cfg.icon
            const latest = latestByType[t]!
            return (
              <Card key={t} className="p-3 flex items-center gap-3">
                <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg" style={{ background: cfg.color + '20', color: cfg.color }}>
                  <TypeIcon className="h-4 w-4" />
                </div>
                <div className="min-w-0">
                  <p className="text-xs text-muted-foreground">{cfg.label}</p>
                  <p className="text-sm font-semibold">{latest.reading} <span className="text-xs font-normal text-muted-foreground">{latest.unit}</span></p>
                  <p className="text-xs text-muted-foreground">{formatDate(latest.reading_date)}</p>
                </div>
              </Card>
            )
          })}
        </div>

        {/* Bar chart */}
        {chartReadings.length > 1 && (
          <Card className="p-4">
            <p className="text-xs text-muted-foreground mb-3 font-medium">
              Last {chartReadings.length} readings {typeFilter !== 'all' ? `— ${METER_CONFIG[typeFilter].label}` : ''}
            </p>
            <div className="flex items-end gap-2 h-24">
              {chartReadings.map((r) => {
                const cfg = METER_CONFIG[r.meter_type]
                const pct = (r.reading / maxReading) * 100
                return (
                  <div key={r.id} className="flex-1 flex flex-col items-center gap-1">
                    <span className="text-[9px] text-muted-foreground">{r.reading}</span>
                    <div
                      className="w-full rounded-t-sm"
                      style={{ height: `${Math.max(4, pct * 0.72)}px`, background: cfg.color }}
                    />
                    <span className="text-[9px] text-muted-foreground truncate w-full text-center">
                      {r.reading_date.slice(5)}
                    </span>
                  </div>
                )
              })}
            </div>
          </Card>
        )}

        {/* Readings list */}
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
            <Zap className="h-10 w-10 opacity-30" />
            <p className="text-sm">No readings yet</p>
            <Button size="sm" onClick={() => setShowForm(true)}><Plus className="h-4 w-4 mr-1" />Log reading</Button>
          </div>
        ) : (
          <Card className="p-0 overflow-hidden">
            <div className="divide-y divide-border/30">
              {filtered.map((r) => {
                const cfg = METER_CONFIG[r.meter_type]
                const TypeIcon = cfg.icon
                return (
                  <div key={r.id} className="flex items-start gap-3 px-4 py-3">
                    <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg mt-0.5" style={{ background: cfg.color + '20', color: cfg.color }}>
                      <TypeIcon className="h-4 w-4" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <p className="text-sm font-medium">{r.reading} <span className="text-xs text-muted-foreground">{r.unit}</span></p>
                        <Badge variant="neutral" style={{ borderColor: cfg.color + '60', color: cfg.color }}>
                          {cfg.label}
                        </Badge>
                        {r.meter_id && <span className="text-xs text-muted-foreground">{r.meter_id}</span>}
                      </div>
                      {r.notes && <p className="text-xs text-muted-foreground mt-0.5">{r.notes}</p>}
                      <p className="text-xs text-muted-foreground/60 mt-0.5">{formatDate(r.reading_date)}</p>
                    </div>
                    <button
                      onClick={() => handleDelete(r)}
                      disabled={deletingId === r.id}
                      className="shrink-0 p-1.5 text-muted-foreground hover:text-destructive transition-colors"
                    >
                      {deletingId === r.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />}
                    </button>
                  </div>
                )
              })}
            </div>
          </Card>
        )}
        {/* Benchmarks card */}
        {readings.length > 0 && (() => {
          const now = new Date()
          const twelveMonthsAgo = new Date(now.getFullYear() - 1, now.getMonth(), 1)
          const areaSqm = property.size_sqm

          const benchmarkCards = BENCHMARKS.map((b) => {
            const relevant = readings.filter((r) =>
              r.meter_type === b.meterType &&
              new Date(r.reading_date + 'T00:00:00') >= twelveMonthsAgo
            )
            if (relevant.length < 2) return null

            // Sum differences between consecutive readings (ordered ascending)
            const sorted = [...relevant].sort((a, c) => a.reading_date.localeCompare(c.reading_date))
            let total = 0
            for (let i = 1; i < sorted.length; i++) {
              // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
              const diff = sorted[i]!.reading - sorted[i - 1]!.reading
              if (diff > 0) total += diff
            }

            let displayValue = total
            let displayUnit = b.unit
            if (b.meterType === 'electricity' && areaSqm && areaSqm > 0) {
              displayValue = Math.round(total / areaSqm)
            }

            const { grade, color, pct } = getBenchmarkLabel(displayValue, b)
            const cfg = METER_CONFIG[b.meterType]
            const TypeIcon = cfg.icon

            return (
              <div key={b.meterType} className="flex items-center gap-3">
                <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg" style={{ background: cfg.color + '20', color: cfg.color }}>
                  <TypeIcon className="h-4 w-4" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="text-sm font-medium">{b.label}</span>
                    <Badge variant="neutral" style={{ borderColor: color + '60', color }}>
                      {grade}
                    </Badge>
                    <span className="text-xs text-muted-foreground">
                      {displayValue.toLocaleString()} {displayUnit}
                    </span>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    {pct > 0 ? `${pct}% above` : `${Math.abs(pct)}% below`} average ({b.good} {displayUnit})
                  </p>
                </div>
              </div>
            )
          }).filter(Boolean)

          if (benchmarkCards.length === 0) return null

          return (
            <Card className="p-4">
              <p className="text-xs text-muted-foreground mb-1 font-medium">Energy Benchmarks</p>
              {areaSqm && (
                <p className="text-xs text-muted-foreground/60 mb-3">Area used for calculation: {areaSqm} m²</p>
              )}
              <div className="flex flex-col gap-3">
                {benchmarkCards}
              </div>
              <div className="mt-3 pt-3 border-t border-border/20 grid grid-cols-4 gap-1 text-[10px] text-center text-muted-foreground">
                <span className="text-green-600 font-medium">Excellent</span>
                <span className="text-[hsl(88,58%,39%)] font-medium">Good</span>
                <span className="text-[hsl(45,75%,42%)] font-medium">Average</span>
                <span className="text-destructive font-medium">Poor</span>
              </div>
            </Card>
          )
        })()}
      </div>

      {/* Log reading modal */}
      {showForm && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-md p-5 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">Log Meter Reading</h2>
              <button onClick={() => setShowForm(false)}><X className="h-4 w-4 text-muted-foreground" /></button>
            </div>
            <form onSubmit={handleSave} className="space-y-3">
              <div className="grid grid-cols-2 gap-3">
                <select
                  value={meterType}
                  onChange={(e) => setMeterType(e.target.value as MeterType)}
                  className="rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                >
                  {METER_TYPES.map((t) => (
                    <option key={t} value={t}>{METER_CONFIG[t].label}</option>
                  ))}
                </select>
                <Input placeholder="Meter ID (optional)" value={meterId} onChange={(e) => setMeterId(e.target.value)} />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <Input placeholder="Reading *" type="number" step="any" value={readingVal} onChange={(e) => setReadingVal(e.target.value)} required />
                <Input placeholder="Unit" value={unit} onChange={(e) => setUnit(e.target.value)} />
              </div>
              <div>
                <label className="text-xs text-muted-foreground">Reading date</label>
                <Input type="date" value={readingDate} onChange={(e) => setReadingDate(e.target.value)} />
              </div>
              <textarea
                placeholder="Notes (optional)"
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                rows={2}
                className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <div className="flex justify-end gap-2">
                <Button type="button" variant="ghost" size="sm" onClick={() => setShowForm(false)}>Cancel</Button>
                <Button type="submit" size="sm" disabled={saving}>
                  {saving && <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />}
                  Log reading
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}
