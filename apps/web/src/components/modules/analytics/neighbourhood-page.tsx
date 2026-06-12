'use client'

import * as React from 'react'
import { MapPin, Plus, Trash2, X, AlertCircle, TrendingUp, TrendingDown } from 'lucide-react'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { createClient } from '@/lib/supabase/client'
import { cn } from '@/lib/utils'
import type { Property } from '@/lib/supabase/types'

interface Benchmark {
  id: string
  property_id: string
  metric: string
  value: number
  unit: string | null
  source: string | null
  recorded_date: string | null
  notes: string | null
  created_by: string | null
  created_at: string
}

interface NeighbourhoodPageProps {
  property: Property
  initialBenchmarks: Benchmark[]
  monthlyExpenses: number
  monthlyRent: number
}

const METRIC_OPTIONS = [
  { value: 'avg_rent_sqm', label: 'Average Rent / m²', unit: '€/m²', description: 'Avg market rent per square metre' },
  { value: 'avg_sale_price_sqm', label: 'Average Sale Price / m²', unit: '€/m²', description: 'Avg sale price per square metre' },
  { value: 'avg_maintenance_annual', label: 'Average Annual Maintenance Cost', unit: '€', description: 'Avg annual maintenance spend' },
  { value: 'avg_utility_monthly', label: 'Average Monthly Utilities', unit: '€', description: 'Avg monthly utility bills' },
  { value: 'avg_yield', label: 'Average Rental Yield', unit: '%', description: 'Avg gross rental yield in the area' },
  { value: 'vacancy_rate', label: 'Area Vacancy Rate', unit: '%', description: 'Percentage of vacant properties' },
  { value: 'custom', label: 'Custom Metric', unit: '', description: 'Add your own benchmark' },
]

// For these metrics, higher own value is WORSE
const HIGHER_IS_WORSE = new Set(['avg_maintenance_annual', 'avg_utility_monthly', 'vacancy_rate'])

function getMetricLabel(metric: string) {
  return METRIC_OPTIONS.find((m) => m.value === metric)?.label ?? metric
}

function getMetricUnit(metric: string, benchmark: Benchmark) {
  if (metric === 'custom') return benchmark.unit ?? ''
  return METRIC_OPTIONS.find((m) => m.value === metric)?.unit ?? benchmark.unit ?? ''
}

function fmtVal(v: number, unit: string) {
  if (unit === '%') return `${v.toFixed(1)}%`
  if (unit === '€/m²') return `€${v.toFixed(0)}/m²`
  if (unit === '€') return `€${v.toLocaleString('en', { maximumFractionDigits: 0 })}`
  return `${v.toLocaleString('en', { maximumFractionDigits: 2 })} ${unit}`
}

function getOwnValue(
  metric: string,
  property: Property,
  monthlyExpenses: number,
  monthlyRent: number,
): number | null {
  const sizeSqm = (property as unknown as Record<string, unknown>).size_sqm as number | null | undefined
  switch (metric) {
    case 'avg_rent_sqm':
      if (!sizeSqm || sizeSqm <= 0 || monthlyRent <= 0) return null
      return (monthlyRent * 12) / sizeSqm
    case 'avg_maintenance_annual':
      return monthlyExpenses * 12
    case 'avg_utility_monthly':
      return monthlyExpenses
    default:
      return null
  }
}

function DeltaBadge({ own, benchmark, metric }: { own: number; benchmark: number; metric: string }) {
  if (benchmark <= 0) return null
  const pct = ((own - benchmark) / benchmark) * 100
  const isWorse = HIGHER_IS_WORSE.has(metric)
  const positive = pct > 0
  // "better" means own < benchmark for worse-when-higher metrics, own > benchmark otherwise
  const isBetter = isWorse ? !positive : positive
  const absRounded = Math.abs(pct).toFixed(1)

  return (
    <span
      className={cn(
        'inline-flex items-center gap-0.5 text-xs font-semibold',
        isBetter ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400',
      )}
    >
      {isBetter ? <TrendingUp className="h-3 w-3" /> : <TrendingDown className="h-3 w-3" />}
      {absRounded}% {isBetter ? 'above avg' : 'below avg'}
    </span>
  )
}

export function NeighbourhoodPage({
  property,
  initialBenchmarks,
  monthlyExpenses,
  monthlyRent,
}: NeighbourhoodPageProps) {
  const [benchmarks, setBenchmarks] = React.useState<Benchmark[]>(initialBenchmarks)
  const [showAdd, setShowAdd] = React.useState(false)
  const [deleteId, setDeleteId] = React.useState<string | null>(null)
  const [saving, setSaving] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)

  // Form state
  const [fMetric, setFMetric] = React.useState('avg_rent_sqm')
  const [fValue, setFValue] = React.useState('')
  const [fUnit, setFUnit] = React.useState('€/m²')
  const [fSource, setFSource] = React.useState('')
  const [fDate, setFDate] = React.useState(new Date().toISOString().split('T')[0]!)
  const [fNotes, setFNotes] = React.useState('')
  const [fCustomLabel, setFCustomLabel] = React.useState('')

  // Auto-fill unit when metric changes
  React.useEffect(() => {
    const found = METRIC_OPTIONS.find((m) => m.value === fMetric)
    if (found && found.unit) setFUnit(found.unit)
  }, [fMetric])

  const supabase = createClient()

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault()
    if (!fValue) return
    setSaving(true)
    setError(null)
    const {
      data: { user },
    } = await supabase.auth.getUser()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data, error: err } = await (supabase as any).from('neighbourhood_benchmarks').insert({
      property_id: property.id,
      metric: fMetric === 'custom' ? (fCustomLabel || 'custom') : fMetric,
      value: parseFloat(fValue),
      unit: fUnit || null,
      source: fSource || null,
      recorded_date: fDate || null,
      notes: fNotes || null,
      created_by: user?.id ?? null,
    }).select().single()

    if (err) {
      setError(err.message)
    } else {
      setBenchmarks((prev) => [data, ...prev].sort((a, b) => a.metric.localeCompare(b.metric)))
      setShowAdd(false)
      setFValue('')
      setFSource('')
      setFNotes('')
      setFCustomLabel('')
    }
    setSaving(false)
  }

  async function handleDelete(id: string) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('neighbourhood_benchmarks').delete().eq('id', id)
    setBenchmarks((prev) => prev.filter((b) => b.id !== id))
    setDeleteId(null)
  }

  // Summary: count metrics where own is better
  const metricsWithComparison = benchmarks.filter((b) => {
    const own = getOwnValue(b.metric, property, monthlyExpenses, monthlyRent)
    return own !== null
  })

  let betterCount = 0
  let totalComparable = 0
  for (const b of metricsWithComparison) {
    const own = getOwnValue(b.metric, property, monthlyExpenses, monthlyRent)
    if (own === null || b.value <= 0) continue
    totalComparable++
    const pct = ((own - b.value) / b.value) * 100
    const isWorse = HIGHER_IS_WORSE.has(b.metric)
    const isBetter = isWorse ? pct < 0 : pct > 0
    if (isBetter) betterCount++
  }

  const summaryText =
    totalComparable > 0
      ? `Your property performs above area average on ${betterCount} of ${totalComparable} comparable metric${totalComparable !== 1 ? 's' : ''}.`
      : null

  return (
    <>
      <PageHeader title="Neighbourhood Benchmarks" description={property.name} backHref="/more" />
      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Summary card */}
        {summaryText && (
          <Card className="flex items-start gap-3 p-4">
            <MapPin className="h-4 w-4 mt-0.5 shrink-0 text-primary" />
            <p className="text-sm text-muted-foreground">{summaryText}</p>
          </Card>
        )}

        {/* Add button */}
        <button
          type="button"
          onClick={() => setShowAdd(true)}
          className="flex items-center justify-center gap-2 rounded-2xl border border-dashed border-border/50 px-4 py-3 text-sm text-muted-foreground transition-colors hover:border-primary/50 hover:text-primary"
        >
          <Plus className="h-4 w-4" />
          Add benchmark
        </button>

        {/* Benchmarks list */}
        {benchmarks.length === 0 ? (
          <Card className="flex items-start gap-3 p-4">
            <AlertCircle className="h-4 w-4 mt-0.5 shrink-0 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">
              No benchmarks recorded yet. Add area comparisons to see how your property stacks up.
            </p>
          </Card>
        ) : (
          <Card className="p-0 overflow-hidden">
            <div className="px-4 py-3 border-b border-border/30">
              <p className="text-sm font-medium">Recorded benchmarks</p>
            </div>
            <div className="divide-y divide-border/30">
              {benchmarks.map((b) => {
                const unit = getMetricUnit(b.metric, b)
                const own = getOwnValue(b.metric, property, monthlyExpenses, monthlyRent)
                return (
                  <div key={b.id} className="flex items-start justify-between gap-3 px-4 py-4">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <p className="text-sm font-medium">{getMetricLabel(b.metric)}</p>
                        {b.source && (
                          <Badge variant="neutral" style={{ fontSize: '10px' }}>
                            {b.source}
                          </Badge>
                        )}
                      </div>
                      <p className="text-xs text-muted-foreground mt-0.5">
                        Area avg: <span className="font-semibold text-foreground">{fmtVal(b.value, unit)}</span>
                        {b.recorded_date && (
                          <span className="ml-2 text-muted-foreground/60">{b.recorded_date}</span>
                        )}
                      </p>
                      {own !== null && (
                        <div className="mt-1 flex items-center gap-2 flex-wrap">
                          <p className="text-xs text-muted-foreground">
                            Your property: <span className="font-semibold text-foreground">{fmtVal(own, unit)}</span>
                          </p>
                          <DeltaBadge own={own} benchmark={b.value} metric={b.metric} />
                        </div>
                      )}
                      {b.notes && <p className="text-xs text-muted-foreground mt-1 italic">{b.notes}</p>}
                    </div>
                    <button
                      type="button"
                      onClick={() => setDeleteId(b.id)}
                      className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg text-muted-foreground hover:text-red-500 transition-colors"
                      aria-label="Delete benchmark"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  </div>
                )
              })}
            </div>
          </Card>
        )}

        <p className="text-xs text-muted-foreground px-1">
          Sources may include Imobiliare.ro, local agents, or your own research. Keep benchmarks updated for accuracy.
        </p>
      </div>

      {/* Add modal */}
      {showAdd && (
        <div
          className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 backdrop-blur-sm md:items-center"
          onClick={(e) => e.target === e.currentTarget && setShowAdd(false)}
        >
          <Card className="w-full max-w-md rounded-t-3xl rounded-b-none md:rounded-2xl p-5 max-h-[90dvh] overflow-y-auto">
            <div className="flex items-center justify-between mb-4">
              <p className="text-base font-semibold">Add Benchmark</p>
              <button
                type="button"
                onClick={() => setShowAdd(false)}
                className="flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground hover:text-foreground"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <form onSubmit={handleAdd} className="flex flex-col gap-3">
              <div>
                <label className="text-xs text-muted-foreground block mb-1">Metric *</label>
                <select
                  value={fMetric}
                  onChange={(e) => setFMetric(e.target.value)}
                  className="w-full rounded-lg border border-border/50 bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40"
                >
                  {METRIC_OPTIONS.map((o) => (
                    <option key={o.value} value={o.value}>
                      {o.label}
                    </option>
                  ))}
                </select>
              </div>

              {fMetric === 'custom' && (
                <div>
                  <label className="text-xs text-muted-foreground block mb-1">Custom metric name *</label>
                  <input
                    type="text"
                    value={fCustomLabel}
                    onChange={(e) => setFCustomLabel(e.target.value)}
                    placeholder="e.g. Avg parking space cost"
                    className="w-full rounded-lg border border-border/50 bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40"
                    required
                  />
                </div>
              )}

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs text-muted-foreground block mb-1">Value *</label>
                  <input
                    type="number"
                    step="any"
                    value={fValue}
                    onChange={(e) => setFValue(e.target.value)}
                    placeholder="0"
                    required
                    className="w-full rounded-lg border border-border/50 bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40"
                  />
                </div>
                <div>
                  <label className="text-xs text-muted-foreground block mb-1">Unit</label>
                  <input
                    type="text"
                    value={fUnit}
                    onChange={(e) => setFUnit(e.target.value)}
                    placeholder="€/m²"
                    className="w-full rounded-lg border border-border/50 bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40"
                  />
                </div>
              </div>

              <div>
                <label className="text-xs text-muted-foreground block mb-1">Source</label>
                <input
                  type="text"
                  value={fSource}
                  onChange={(e) => setFSource(e.target.value)}
                  placeholder="e.g. Imobiliare.ro, Local agent"
                  className="w-full rounded-lg border border-border/50 bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40"
                />
              </div>

              <div>
                <label className="text-xs text-muted-foreground block mb-1">Recorded date</label>
                <input
                  type="date"
                  value={fDate}
                  onChange={(e) => setFDate(e.target.value)}
                  className="w-full rounded-lg border border-border/50 bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40"
                />
              </div>

              <div>
                <label className="text-xs text-muted-foreground block mb-1">Notes</label>
                <textarea
                  value={fNotes}
                  onChange={(e) => setFNotes(e.target.value)}
                  rows={2}
                  placeholder="Optional notes..."
                  className="w-full rounded-lg border border-border/50 bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40 resize-none"
                />
              </div>

              {error && <p className="text-xs text-red-500">{error}</p>}

              <button
                type="submit"
                disabled={saving || !fValue}
                className="mt-1 rounded-xl bg-primary px-4 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-primary/80 disabled:opacity-50"
              >
                {saving ? 'Saving…' : 'Add benchmark'}
              </button>
            </form>
          </Card>
        </div>
      )}

      {/* Delete confirm */}
      {deleteId && (
        <div
          className="fixed inset-0 z-50 flex items-end md:items-center justify-center bg-black/40 backdrop-blur-sm p-4"
          onClick={(e) => e.target === e.currentTarget && setDeleteId(null)}
        >
          <Card className="w-full max-w-sm p-5 max-h-[90vh] overflow-y-auto">
            <p className="text-base font-semibold mb-2">Delete benchmark?</p>
            <p className="text-sm text-muted-foreground mb-4">This action cannot be undone.</p>
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => setDeleteId(null)}
                className="flex-1 rounded-xl border border-border/50 px-4 py-2 text-sm font-medium transition-colors hover:bg-muted/50"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={() => handleDelete(deleteId)}
                className="flex-1 rounded-xl bg-red-500 px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-red-600"
              >
                Delete
              </button>
            </div>
          </Card>
        </div>
      )}
    </>
  )
}
