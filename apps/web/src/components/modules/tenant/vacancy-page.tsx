'use client'

import * as React from 'react'
import {
  DoorOpen, Plus, X, Loader2, Trash2, Pencil,
} from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import type { Property } from '@/lib/supabase/types'

interface Vacancy {
  id: string
  property_id: string
  start_date: string
  end_date: string | null
  reason: string | null
  expected_rent_loss: number | null
  currency: string | null
  notes: string | null
  created_by: string | null
  created_at: string
}

interface VacancyPageProps {
  property: Property
  userId: string
  initialVacancies: Vacancy[]
}

function parseDate(d: string) {
  return new Date(d + 'T00:00:00')
}

function daysBetween(start: Date, end: Date): number {
  return Math.max(0, Math.ceil((end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24)))
}

function vacancyDays(v: Vacancy): number {
  const start = parseDate(v.start_date)
  const end = v.end_date ? parseDate(v.end_date) : new Date()
  return daysBetween(start, end)
}

function vacancyDaysThisYear(v: Vacancy): number {
  const yearStart = new Date(new Date().getFullYear(), 0, 1)
  const yearEnd = new Date(new Date().getFullYear(), 11, 31)
  const start = parseDate(v.start_date)
  const end = v.end_date ? parseDate(v.end_date) : new Date()
  const effectiveStart = start < yearStart ? yearStart : start
  const effectiveEnd = end > yearEnd ? yearEnd : end
  if (effectiveStart >= effectiveEnd) return 0
  return daysBetween(effectiveStart, effectiveEnd)
}

function formatDate(d: string | null) {
  if (!d) return '—'
  return new Date(d + 'T00:00:00').toLocaleDateString('en', { day: 'numeric', month: 'short', year: 'numeric' })
}

function formatMoney(v: number | null | undefined, currency: string | null | undefined) {
  if (v == null) return '—'
  return `${v.toLocaleString('en', { maximumFractionDigits: 2 })} ${currency ?? ''}`.trim()
}

// Simple SVG donut chart
function OccupancyDonut({ percent }: { percent: number }) {
  const r = 54
  const cx = 64
  const cy = 64
  const circumference = 2 * Math.PI * r
  const filled = (percent / 100) * circumference
  const gap = circumference - filled

  const color = percent >= 90 ? '#16a34a' : percent >= 70 ? '#ca8a04' : '#dc2626'

  return (
    <svg width="128" height="128" viewBox="0 0 128 128">
      {/* Background track */}
      <circle
        cx={cx} cy={cy} r={r}
        fill="none"
        stroke="currentColor"
        strokeWidth="12"
        className="text-muted-foreground/10"
      />
      {/* Progress arc */}
      <circle
        cx={cx} cy={cy} r={r}
        fill="none"
        stroke={color}
        strokeWidth="12"
        strokeLinecap="round"
        strokeDasharray={`${filled} ${gap}`}
        transform={`rotate(-90 ${cx} ${cy})`}
        style={{ transition: 'stroke-dasharray 0.5s ease' }}
      />
      <text x={cx} y={cy - 6} textAnchor="middle" fill={color} fontSize="20" fontWeight="700">
        {Math.round(percent)}%
      </text>
      <text x={cx} y={cy + 14} textAnchor="middle" fill="#6b7280" fontSize="10">
        occupancy
      </text>
    </svg>
  )
}

const EMPTY_FORM = {
  start_date: '',
  end_date: '',
  reason: '',
  expected_rent_loss: '',
  currency: 'EUR',
  notes: '',
}

export function VacancyPage({ property, userId, initialVacancies }: VacancyPageProps) {
  const confirmDialog = useConfirm()
  const [vacancies, setVacancies] = React.useState<Vacancy[]>(initialVacancies)
  const [showModal, setShowModal] = React.useState(false)
  const [editId, setEditId] = React.useState<string | null>(null)
  const [saving, setSaving] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [form, setForm] = React.useState(EMPTY_FORM)

  // Summary stats
  const totalVacancyDaysThisYear = vacancies.reduce((sum, v) => sum + vacancyDaysThisYear(v), 0)
  const occupancyRate = Math.max(0, Math.min(100, ((365 - totalVacancyDaysThisYear) / 365) * 100))
  const totalRentLoss = vacancies.reduce((sum, v) => sum + (v.expected_rent_loss ?? 0), 0)
  const primaryCurrency = vacancies.find((v) => v.currency)?.currency ?? null

  const occupancyColor = occupancyRate >= 90 ? 'hsl(152,62%,38%)' : occupancyRate >= 70 ? 'hsl(45,75%,42%)' : 'hsl(0,68%,44%)'

  function openNew() {
    setEditId(null)
    setForm(EMPTY_FORM)
    setShowModal(true)
  }

  function openEdit(v: Vacancy) {
    setEditId(v.id)
    setForm({
      start_date: v.start_date,
      end_date: v.end_date ?? '',
      reason: v.reason ?? '',
      expected_rent_loss: v.expected_rent_loss != null ? String(v.expected_rent_loss) : '',
      currency: v.currency ?? 'EUR',
      notes: v.notes ?? '',
    })
    setShowModal(true)
  }

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    if (!form.start_date) return
    setSaving(true)
    try {
      const supabase = createClient()
      const payload = {
        property_id: property.id,
        start_date: form.start_date,
        end_date: form.end_date || null,
        reason: form.reason.trim() || null,
        expected_rent_loss: form.expected_rent_loss ? parseFloat(form.expected_rent_loss) : null,
        currency: form.currency || null,
        notes: form.notes.trim() || null,
        created_by: userId,
      }
      if (editId) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data, error } = await (supabase as any)
          .from('vacancies').update(payload).eq('id', editId).select().single()
        if (error) throw error
        setVacancies((prev) => prev.map((x) => (x.id === editId ? data as Vacancy : x)))
        toast({ title: 'Vacancy updated' })
      } else {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data, error } = await (supabase as any)
          .from('vacancies').insert(payload).select().single()
        if (error) throw error
        setVacancies((prev) => [data as Vacancy, ...prev])
        toast({ title: 'Vacancy added' })
      }
      setShowModal(false)
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete(v: Vacancy) {
    const ok = await confirmDialog({
      title: 'Delete vacancy',
      description: 'Delete this vacancy record? This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(v.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('vacancies').delete().eq('id', v.id)
      setVacancies((prev) => prev.filter((x) => x.id !== v.id))
      toast({ title: 'Vacancy deleted' })
    } finally {
      setDeletingId(null)
    }
  }

  return (
    <>
      <PageHeader
        title="Vacancies"
        description={property.name}
        action={{ label: 'Add Vacancy', href: '#', onClick: openNew }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Summary stats */}
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <Card className="p-4 flex flex-col items-center justify-center gap-1">
            <OccupancyDonut percent={occupancyRate} />
          </Card>
          <Card className="p-4 flex flex-col gap-1">
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Vacancy Days This Year</p>
            <p className="text-2xl font-bold" style={{ color: occupancyColor }}>{totalVacancyDaysThisYear}</p>
            <p className="text-xs text-muted-foreground">out of 365 days</p>
          </Card>
          <Card className="p-4 flex flex-col gap-1">
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Est. Rent Loss</p>
            <p className="text-2xl font-bold text-destructive">{formatMoney(totalRentLoss || null, primaryCurrency)}</p>
            <p className="text-xs text-muted-foreground">total estimated</p>
          </Card>
        </div>

        {vacancies.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
            <DoorOpen className="h-10 w-10 opacity-30" />
            <p className="text-sm">No vacancy periods recorded</p>
            <Button size="sm" onClick={openNew}><Plus className="h-4 w-4 mr-1" />Add Vacancy</Button>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {vacancies.map((v) => {
              const days = vacancyDays(v)
              const ongoing = !v.end_date
              return (
                <Card key={v.id} className="p-4">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-start gap-3 flex-1">
                      <div
                        className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg mt-0.5"
                        style={{ background: occupancyColor + '20', color: occupancyColor }}
                      >
                        <DoorOpen className="h-4 w-4" />
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2 flex-wrap">
                          <p className="font-semibold text-sm">
                            {formatDate(v.start_date)} → {ongoing ? 'Ongoing' : formatDate(v.end_date)}
                          </p>
                          {ongoing && (
                            <Badge variant="neutral" style={{ borderColor: 'hsl(45,75%,42%)60', color: 'hsl(45,75%,42%)' }}>
                              Ongoing
                            </Badge>
                          )}
                        </div>
                        <p className="text-xs text-muted-foreground mt-0.5">
                          {days} days
                          {v.reason && ` · ${v.reason}`}
                          {v.expected_rent_loss != null && ` · Loss: ${formatMoney(v.expected_rent_loss, v.currency)}`}
                        </p>
                        {v.notes && <p className="text-xs text-muted-foreground mt-1">{v.notes}</p>}
                      </div>
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      <button
                        onClick={() => openEdit(v)}
                        className="p-1.5 rounded-lg hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
                      >
                        <Pencil className="h-3.5 w-3.5" />
                      </button>
                      <button
                        onClick={() => handleDelete(v)}
                        disabled={deletingId === v.id}
                        className="p-1.5 rounded-lg hover:bg-destructive/10 transition-colors text-muted-foreground hover:text-destructive"
                      >
                        {deletingId === v.id
                          ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                          : <Trash2 className="h-3.5 w-3.5" />}
                      </button>
                    </div>
                  </div>
                </Card>
              )
            })}
          </div>
        )}
      </div>

      {showModal && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-md p-5 space-y-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">{editId ? 'Edit Vacancy' : 'Add Vacancy'}</h2>
              <button onClick={() => setShowModal(false)}>
                <X className="h-4 w-4 text-muted-foreground" />
              </button>
            </div>
            <form onSubmit={handleSave} className="space-y-3">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs text-muted-foreground">Start date *</label>
                  <Input
                    type="date"
                    value={form.start_date}
                    onChange={(e) => setForm((f) => ({ ...f, start_date: e.target.value }))}
                    required
                  />
                </div>
                <div>
                  <label className="text-xs text-muted-foreground">End date</label>
                  <Input
                    type="date"
                    value={form.end_date}
                    onChange={(e) => setForm((f) => ({ ...f, end_date: e.target.value }))}
                  />
                </div>
              </div>
              <Input
                placeholder="Reason (e.g. between tenants)"
                value={form.reason}
                onChange={(e) => setForm((f) => ({ ...f, reason: e.target.value }))}
              />
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs text-muted-foreground">Est. rent loss</label>
                  <Input
                    type="number"
                    step="0.01"
                    min="0"
                    placeholder="0.00"
                    value={form.expected_rent_loss}
                    onChange={(e) => setForm((f) => ({ ...f, expected_rent_loss: e.target.value }))}
                  />
                </div>
                <div>
                  <label className="text-xs text-muted-foreground">Currency</label>
                  <Input
                    value={form.currency}
                    onChange={(e) => setForm((f) => ({ ...f, currency: e.target.value }))}
                  />
                </div>
              </div>
              <textarea
                placeholder="Notes (optional)"
                value={form.notes}
                onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))}
                rows={2}
                className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <div className="flex justify-end gap-2">
                <Button type="button" variant="ghost" size="sm" onClick={() => setShowModal(false)}>Cancel</Button>
                <Button type="submit" size="sm" disabled={saving}>
                  {saving && <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />}
                  {editId ? 'Save changes' : 'Add vacancy'}
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}
