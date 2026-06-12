'use client'

import * as React from 'react'
import { TrendingUp, TrendingDown, Plus, X, Loader2, DollarSign, Calendar } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { toast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import type { Property } from '@/lib/supabase/types'

interface Valuation {
  id: string
  property_id: string
  valuation_date: string
  estimated_value: number
  source: string | null
  notes: string | null
  created_at: string
}

interface PropertyValuePageProps {
  property: Property
  userId: string
  initialValuations: Valuation[]
}

const SOURCES = [
  { value: 'manual',               label: 'Manual estimate' },
  { value: 'professional_appraisal', label: 'Professional appraisal' },
  { value: 'zillow',               label: 'Zillow' },
  { value: 'rightmove',            label: 'Rightmove' },
  { value: 'idealista',            label: 'Idealista' },
  { value: 'other',                label: 'Other' },
]

function fmtMoney(v: number) {
  return `€${v.toLocaleString('en', { maximumFractionDigits: 0 })}`
}

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString('en', { year: 'numeric', month: 'short', day: 'numeric' })
}

export function PropertyValuePage({ property, userId, initialValuations }: PropertyValuePageProps) {
  const [valuations, setValuations] = React.useState<Valuation[]>(initialValuations)
  const [showForm, setShowForm] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [value, setValue] = React.useState('')
  const [date, setDate] = React.useState(() => new Date().toISOString().split('T')[0]!)
  const [source, setSource] = React.useState('manual')
  const [notes, setNotes] = React.useState('')

  const latest = valuations.at(-1)
  const previous = valuations.at(-2)
  const delta = latest && previous ? latest.estimated_value - previous.estimated_value : null
  const deltaPercent = delta != null && previous ? (delta / previous.estimated_value) * 100 : null
  const purchasePrice = (property as unknown as { purchase_price?: number | null }).purchase_price ?? null

  const chartMax = valuations.length ? Math.max(...valuations.map((v) => v.estimated_value)) * 1.05 : 0

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault()
    if (!value) return
    setSaving(true)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('property_valuations')
        .insert({
          property_id: property.id,
          valuation_date: date,
          estimated_value: parseFloat(value),
          source: source || null,
          notes: notes.trim() || null,
          created_by: userId,
        })
        .select()
        .single()
      if (error) throw error
      setValuations((prev) => [...prev, data].sort((a, b) => a.valuation_date.localeCompare(b.valuation_date)))
      setValue(''); setNotes(''); setShowForm(false)
      toast({ title: 'Valuation added' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  return (
    <>
      <PageHeader
        title="Property Value"
        description={property.name}
        backHref="/property"
        action={{ label: 'Add Valuation', href: '#', onClick: () => setShowForm(true) }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* KPI row */}
        <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          <StatCard label="Current value" value={latest ? fmtMoney(latest.estimated_value) : '—'} />
          <StatCard label="Valuations" value={String(valuations.length)} />
          {delta != null && (
            <StatCard
              label="Last change"
              value={`${delta >= 0 ? '+' : ''}${fmtMoney(delta)}`}
              trend={delta >= 0 ? 'up' : 'down'}
            />
          )}
          {purchasePrice && latest ? (
            <StatCard
              label="vs purchase"
              value={`${((latest.estimated_value - purchasePrice) / purchasePrice * 100).toFixed(1)}%`}
              trend={latest.estimated_value >= purchasePrice ? 'up' : 'down'}
            />
          ) : (
            <StatCard label="Valuations" value={String(valuations.length)} />
          )}
        </div>

        {/* Sparkline chart */}
        {valuations.length >= 2 ? (
          <Card className="p-4">
            <p className="text-xs font-medium text-muted-foreground mb-3">Value over time</p>
            <div className="relative h-28 flex items-end gap-1">
              {valuations.map((v, i) => {
                const h = chartMax > 0 ? (v.estimated_value / chartMax) * 100 : 50
                const isLatest = i === valuations.length - 1
                return (
                  <div key={v.id} className="flex flex-col items-center gap-1 flex-1 min-w-0" title={`${fmtDate(v.valuation_date)}: ${fmtMoney(v.estimated_value)}`}>
                    <div
                      className={cn('w-full rounded-t-sm transition-all', isLatest ? 'bg-primary' : 'bg-primary/30')}
                      style={{ height: `${h}%` }}
                    />
                  </div>
                )
              })}
            </div>
            <div className="flex justify-between text-xs text-muted-foreground mt-1">
              <span>{valuations[0] ? fmtDate(valuations[0].valuation_date) : ''}</span>
              <span>{latest ? fmtDate(latest.valuation_date) : ''}</span>
            </div>
          </Card>
        ) : null}

        {/* History list */}
        <Card className="p-0 overflow-hidden">
          <div className="px-4 py-3 border-b border-border/30">
            <p className="text-sm font-medium">Valuation History</p>
          </div>
          {valuations.length === 0 ? (
            <div className="flex flex-col items-center gap-2 py-10 text-muted-foreground">
              <DollarSign className="h-8 w-8 opacity-30" />
              <p className="text-sm">No valuations yet</p>
              <Button size="sm" onClick={() => setShowForm(true)}><Plus className="h-3.5 w-3.5 mr-1" />Add first valuation</Button>
            </div>
          ) : (
            <div className="divide-y divide-border/30">
              {[...valuations].reverse().map((v) => (
                <div key={v.id} className="flex items-center justify-between px-4 py-3 gap-3">
                  <div className="flex items-center gap-3">
                    <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/10 text-primary">
                      <DollarSign className="h-4 w-4" />
                    </div>
                    <div>
                      <p className="text-sm font-semibold">{fmtMoney(v.estimated_value)}</p>
                      <p className="text-xs text-muted-foreground">{fmtDate(v.valuation_date)}</p>
                    </div>
                  </div>
                  <div className="text-right">
                    {v.source && <p className="text-xs text-muted-foreground capitalize">{v.source.replace(/_/g, ' ')}</p>}
                    {v.notes && <p className="text-xs text-muted-foreground truncate max-w-[140px]">{v.notes}</p>}
                  </div>
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>

      {showForm && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-md p-5 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">Add Valuation</h2>
              <button onClick={() => setShowForm(false)}><X className="h-4 w-4 text-muted-foreground" /></button>
            </div>
            <form onSubmit={handleAdd} className="space-y-3">
              <Input placeholder="Estimated value (€) *" type="number" min="0" step="1000" value={value} onChange={(e) => setValue(e.target.value)} required />
              <div>
                <label className="text-xs text-muted-foreground">Valuation date</label>
                <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} required />
              </div>
              <select
                value={source}
                onChange={(e) => setSource(e.target.value)}
                className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
              >
                {SOURCES.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
              </select>
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
                  Add valuation
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}

function StatCard({ label, value, trend }: { label: string; value: string; trend?: 'up' | 'down' }) {
  return (
    <Card className="p-3 flex flex-col gap-1">
      <p className="text-xs text-muted-foreground">{label}</p>
      <div className="flex items-center gap-1">
        <p className="text-base font-bold">{value}</p>
        {trend === 'up' && <TrendingUp className="h-3.5 w-3.5 text-green-500" />}
        {trend === 'down' && <TrendingDown className="h-3.5 w-3.5 text-red-500" />}
      </div>
    </Card>
  )
}
