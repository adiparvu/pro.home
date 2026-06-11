'use client'

import * as React from 'react'
import {
  FileSignature, Plus, X, Loader2, Trash2, Pencil, ChevronDown, ChevronUp,
  AlertTriangle, Calendar, DollarSign, Mail, FileText, ExternalLink, Sparkles,
  CheckCircle2, XCircle,
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

interface LeaseAnalysis {
  obligations: string[]
  redFlags: string[]
  importantDates: string[]
  rentEscalation: string
  depositConditions: string
  summary: string
}

interface Lease {
  id: string
  property_id: string
  tenant_user_id: string | null
  tenant_name: string
  tenant_email: string | null
  start_date: string
  end_date: string | null
  monthly_rent: number
  currency: string | null
  deposit_amount: number | null
  deposit_paid: boolean | null
  payment_day: number | null
  status: 'active' | 'ending' | 'expired' | 'draft' | 'terminated'
  notes: string | null
  document_url: string | null
  created_by: string | null
}

interface RentPayment {
  id: string
  lease_id: string
  property_id: string
  month: string
  amount: number
  currency: string | null
  received_at: string | null
  payment_method: string | null
  notes: string | null
  receipt_url: string | null
  created_by: string | null
  created_at: string
}

interface LeasePageProps {
  property: Property
  userId: string
  initialLeases: Lease[]
  initialPayments: RentPayment[]
}

const STATUS_CONFIG: Record<Lease['status'], { label: string; color: string }> = {
  active:     { label: 'Active',      color: 'hsl(152,62%,38%)' },
  ending:     { label: 'Ending Soon', color: 'hsl(45,75%,42%)'  },
  expired:    { label: 'Expired',     color: 'hsl(0,68%,44%)'   },
  draft:      { label: 'Draft',       color: 'hsl(220,15%,50%)' },
  terminated: { label: 'Terminated',  color: 'hsl(0,68%,44%)'   },
}

const PAYMENT_METHODS = ['bank_transfer', 'cash', 'online', 'other']

function formatDate(d: string | null) {
  if (!d) return '—'
  return new Date(d + 'T00:00:00').toLocaleDateString('en', { day: 'numeric', month: 'short', year: 'numeric' })
}

function daysUntil(dateStr: string | null): number | null {
  if (!dateStr) return null
  const diff = new Date(dateStr + 'T00:00:00').getTime() - Date.now()
  return Math.ceil(diff / (1000 * 60 * 60 * 24))
}

function formatMoney(v: number | null, currency: string | null) {
  if (v == null) return '—'
  return `${v.toLocaleString('en', { maximumFractionDigits: 2 })} ${currency ?? ''}`.trim()
}

function getLast12Months(): string[] {
  const months: string[] = []
  const now = new Date()
  for (let i = 11; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1)
    months.push(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`)
  }
  return months
}

function formatMonthLabel(ym: string): string {
  const parts = ym.split('-')
  const d = new Date(parseInt(parts[0] ?? '0'), parseInt(parts[1] ?? '1') - 1, 1)
  return d.toLocaleDateString('en', { month: 'short', year: '2-digit' })
}

interface PaymentHistoryProps {
  lease: Lease
  payments: RentPayment[]
  userId: string
  propertyId: string
  onPaymentAdded: (p: RentPayment) => void
}

function PaymentHistory({ lease, payments, userId, propertyId, onPaymentAdded }: PaymentHistoryProps) {
  const months = getLast12Months()
  const currentMonth = months[months.length - 1]!
  const paymentMap = React.useMemo(() => {
    const map: Record<string, RentPayment> = {}
    for (const p of payments) {
      if (p.lease_id === lease.id) map[p.month] = p
    }
    return map
  }, [payments, lease.id])

  const [showModal, setShowModal] = React.useState(false)
  const [saving, setSaving] = React.useState(false)

  const [pmMonth, setPmMonth] = React.useState(currentMonth)
  const [pmAmount, setPmAmount] = React.useState(String(lease.monthly_rent ?? ''))
  const [pmCurrency, setPmCurrency] = React.useState(lease.currency ?? 'EUR')
  const [pmReceivedAt, setPmReceivedAt] = React.useState(new Date().toISOString().slice(0, 10))
  const [pmMethod, setPmMethod] = React.useState('bank_transfer')
  const [pmNotes, setPmNotes] = React.useState('')

  const selectCls = 'w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30'

  function openRecordModal(month: string) {
    setPmMonth(month)
    setPmAmount(String(lease.monthly_rent ?? ''))
    setPmCurrency(lease.currency ?? 'EUR')
    setPmReceivedAt(new Date().toISOString().slice(0, 10))
    setPmMethod('bank_transfer')
    setPmNotes('')
    setShowModal(true)
  }

  async function handleRecord(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('rent_payments')
        .upsert({
          lease_id: lease.id,
          property_id: propertyId,
          month: pmMonth,
          amount: parseFloat(pmAmount),
          currency: pmCurrency || null,
          received_at: pmReceivedAt || null,
          payment_method: pmMethod || null,
          notes: pmNotes.trim() || null,
          created_by: userId,
        }, { onConflict: 'lease_id,month' })
        .select()
        .single()
      if (error) throw error
      onPaymentAdded(data as RentPayment)
      setShowModal(false)
      toast({ title: 'Payment recorded' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="mt-4 pt-4 border-t border-border/30">
      <div className="flex items-center justify-between mb-3">
        <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Payment History (last 12 months)</p>
        <Button variant="ghost" size="sm" className="h-7 px-2 text-xs" onClick={() => openRecordModal(currentMonth)}>
          <Plus className="h-3 w-3 mr-1" />Record payment
        </Button>
      </div>
      <div className="grid grid-cols-6 gap-1.5 md:grid-cols-12">
        {months.map((month) => {
          const paid = paymentMap[month]
          return (
            <div key={month} className="flex flex-col items-center gap-1">
              {paid ? (
                <CheckCircle2 className="h-5 w-5 text-green-600" />
              ) : (
                <button
                  onClick={() => openRecordModal(month)}
                  className="focus:outline-none hover:scale-110 transition-transform"
                  title={`Mark ${formatMonthLabel(month)} as received`}
                >
                  <XCircle className="h-5 w-5 text-destructive/60 hover:text-destructive" />
                </button>
              )}
              <span className="text-[9px] text-muted-foreground">{formatMonthLabel(month)}</span>
              {paid && paid.amount != null && (
                <span className="text-[8px] text-green-700 font-medium">{paid.amount.toLocaleString()}</span>
              )}
            </div>
          )
        })}
      </div>

      {showModal && (
        <div className="fixed inset-0 z-[60] flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-sm p-5 space-y-3 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold text-sm">Record Payment</h2>
              <button onClick={() => setShowModal(false)}><X className="h-4 w-4 text-muted-foreground" /></button>
            </div>
            <form onSubmit={handleRecord} className="space-y-3">
              <div>
                <label className="text-xs text-muted-foreground">Month</label>
                <Input type="month" value={pmMonth} onChange={(e) => setPmMonth(e.target.value)} required />
              </div>
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="text-xs text-muted-foreground">Amount *</label>
                  <Input type="number" step="0.01" min="0" value={pmAmount} onChange={(e) => setPmAmount(e.target.value)} required />
                </div>
                <div>
                  <label className="text-xs text-muted-foreground">Currency</label>
                  <Input value={pmCurrency} onChange={(e) => setPmCurrency(e.target.value)} />
                </div>
              </div>
              <div>
                <label className="text-xs text-muted-foreground">Received on</label>
                <Input type="date" value={pmReceivedAt} onChange={(e) => setPmReceivedAt(e.target.value)} />
              </div>
              <div>
                <label className="text-xs text-muted-foreground">Payment method</label>
                <select value={pmMethod} onChange={(e) => setPmMethod(e.target.value)} className={selectCls}>
                  {PAYMENT_METHODS.map((m) => (
                    <option key={m} value={m}>{m.replace('_', ' ')}</option>
                  ))}
                </select>
              </div>
              <textarea
                placeholder="Notes (optional)"
                value={pmNotes}
                onChange={(e) => setPmNotes(e.target.value)}
                rows={2}
                className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <div className="flex justify-end gap-2">
                <Button type="button" variant="ghost" size="sm" onClick={() => setShowModal(false)}>Cancel</Button>
                <Button type="submit" size="sm" disabled={saving}>
                  {saving && <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />}
                  Save
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </div>
  )
}

const EMPTY_FORM = {
  tenant_name: '',
  tenant_email: '',
  start_date: '',
  end_date: '',
  monthly_rent: '',
  currency: 'EUR',
  deposit_amount: '',
  deposit_paid: false,
  payment_day: '1',
  notes: '',
  document_url: '',
  status: 'active' as Lease['status'],
}

export function LeasePage({ property, userId, initialLeases, initialPayments }: LeasePageProps) {
  const confirmDialog = useConfirm()
  const [leases, setLeases] = React.useState<Lease[]>(initialLeases)
  const [payments, setPayments] = React.useState<RentPayment[]>(initialPayments)
  const [expandedId, setExpandedId] = React.useState<string | null>(null)
  const [showForm, setShowForm] = React.useState(false)
  const [editId, setEditId] = React.useState<string | null>(null)
  const [saving, setSaving] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)

  const [analyseLeaseId, setAnalyseLeaseId] = React.useState<string | null>(null)
  const [leaseText, setLeaseText] = React.useState('')
  const [analysing, setAnalysing] = React.useState(false)
  const [analysisResult, setAnalysisResult] = React.useState<LeaseAnalysis | null>(null)

  const [form, setForm] = React.useState(EMPTY_FORM)

  function setField<K extends keyof typeof EMPTY_FORM>(k: K, v: typeof EMPTY_FORM[K]) {
    setForm((prev) => ({ ...prev, [k]: v }))
  }

  function openNew() {
    setEditId(null)
    setForm(EMPTY_FORM)
    setShowForm(true)
  }

  function openEdit(l: Lease) {
    setEditId(l.id)
    setForm({
      tenant_name: l.tenant_name,
      tenant_email: l.tenant_email ?? '',
      start_date: l.start_date,
      end_date: l.end_date ?? '',
      monthly_rent: l.monthly_rent ? String(l.monthly_rent) : '',
      currency: l.currency ?? 'EUR',
      deposit_amount: l.deposit_amount ? String(l.deposit_amount) : '',
      deposit_paid: l.deposit_paid ?? false,
      payment_day: l.payment_day ? String(l.payment_day) : '1',
      notes: l.notes ?? '',
      document_url: l.document_url ?? '',
      status: l.status,
    })
    setShowForm(true)
  }

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    if (!form.tenant_name.trim() || !form.monthly_rent || !form.start_date) return
    setSaving(true)
    try {
      const supabase = createClient()
      const payload = {
        property_id: property.id,
        tenant_name: form.tenant_name.trim(),
        tenant_email: form.tenant_email.trim() || null,
        start_date: form.start_date,
        end_date: form.end_date || null,
        monthly_rent: parseFloat(form.monthly_rent),
        currency: form.currency || null,
        deposit_amount: form.deposit_amount ? parseFloat(form.deposit_amount) : null,
        deposit_paid: form.deposit_paid,
        payment_day: form.payment_day ? parseInt(form.payment_day) : null,
        notes: form.notes.trim() || null,
        document_url: form.document_url.trim() || null,
        status: form.status,
        created_by: userId,
      }
      if (editId) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data, error } = await (supabase as any)
          .from('leases').update(payload).eq('id', editId).select().single()
        if (error) throw error
        setLeases((prev) => prev.map((l) => (l.id === editId ? data : l)))
        toast({ title: 'Lease updated' })
      } else {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data, error } = await (supabase as any)
          .from('leases').insert(payload).select().single()
        if (error) throw error
        setLeases((prev) => [data, ...prev])
        toast({ title: 'Lease added' })
      }
      setShowForm(false)
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete(l: Lease) {
    const ok = await confirmDialog({
      title: 'Delete lease',
      description: `Delete lease for "${l.tenant_name}"? This cannot be undone.`,
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(l.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('leases').delete().eq('id', l.id)
      setLeases((prev) => prev.filter((x) => x.id !== l.id))
      toast({ title: 'Lease deleted' })
    } finally {
      setDeletingId(null)
    }
  }

  async function handleTerminate(l: Lease) {
    const ok = await confirmDialog({
      title: 'Terminate lease',
      description: `Terminate lease for "${l.tenant_name}"?`,
      confirmLabel: 'Terminate',
      destructive: true,
    })
    if (!ok) return
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('leases').update({ status: 'terminated' }).eq('id', l.id).select().single()
      if (error) throw error
      setLeases((prev) => prev.map((x) => (x.id === l.id ? data : x)))
      toast({ title: 'Lease terminated' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    }
  }

  function openAnalyse(l: Lease) {
    setAnalyseLeaseId(l.id)
    setLeaseText('')
    setAnalysisResult(null)
  }

  function closeAnalyse() {
    setAnalyseLeaseId(null)
    setLeaseText('')
    setAnalysisResult(null)
  }

  async function handleAnalyse() {
    if (!leaseText.trim() || !analyseLeaseId) return
    setAnalysing(true)
    setAnalysisResult(null)
    try {
      const res = await fetch('/api/ai/lease-analysis', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ lease_id: analyseLeaseId, lease_text: leaseText }),
      })
      const json = await res.json() as LeaseAnalysis & { error?: string }
      if (!res.ok || json.error) {
        toast({ title: 'Analysis failed', description: json.error ?? 'Unknown error', variant: 'destructive' })
        return
      }
      setAnalysisResult(json)
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setAnalysing(false)
    }
  }

  function handlePaymentAdded(p: RentPayment) {
    setPayments((prev) => {
      const existing = prev.findIndex((x) => x.lease_id === p.lease_id && x.month === p.month)
      if (existing >= 0) {
        const next = [...prev]
        next[existing] = p
        return next
      }
      return [p, ...prev]
    })
  }

  const selectCls = 'w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30'

  return (
    <>
      <PageHeader
        title="Leases"
        description={property.name}
        action={{ label: 'Add Lease', href: '#', onClick: openNew }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {leases.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
            <FileSignature className="h-10 w-10 opacity-30" />
            <p className="text-sm">No leases yet</p>
            <Button size="sm" onClick={openNew}><Plus className="h-4 w-4 mr-1" />Add Lease</Button>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {leases.map((l) => {
              const cfg = STATUS_CONFIG[l.status]
              const days = daysUntil(l.end_date)
              const endingSoon = l.end_date && days !== null && days >= 0 && days <= 60
              const isExpanded = expandedId === l.id

              return (
                <Card key={l.id} className="p-4">
                  <div className="flex items-start justify-between gap-2">
                    <button
                      className="flex items-start gap-3 flex-1 text-left"
                      onClick={() => setExpandedId(isExpanded ? null : l.id)}
                    >
                      <div
                        className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg mt-0.5"
                        style={{ background: cfg.color + '20', color: cfg.color }}
                      >
                        <FileSignature className="h-4 w-4" />
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2 flex-wrap">
                          <p className="font-semibold text-sm">{l.tenant_name}</p>
                          <Badge variant="neutral" style={{ borderColor: cfg.color + '60', color: cfg.color }}>
                            {cfg.label}
                          </Badge>
                          {endingSoon && (
                            <Badge variant="neutral" style={{ borderColor: 'hsl(45,75%,42%)', color: 'hsl(45,75%,42%)' }}>
                              <AlertTriangle className="h-3 w-3 mr-1" />
                              {days === 0 ? 'Ends today' : `${days}d left`}
                            </Badge>
                          )}
                        </div>
                        <div className="flex items-center gap-3 mt-1 text-xs text-muted-foreground flex-wrap">
                          <span className="flex items-center gap-1">
                            <Calendar className="h-3 w-3" />
                            {formatDate(l.start_date)} → {l.end_date ? formatDate(l.end_date) : 'Open-ended'}
                          </span>
                          <span className="flex items-center gap-1">
                            <DollarSign className="h-3 w-3" />
                            {formatMoney(l.monthly_rent, l.currency)}/mo
                          </span>
                        </div>
                      </div>
                      <span className="text-muted-foreground mt-1">
                        {isExpanded ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                      </span>
                    </button>
                    <div className="flex items-center gap-1 shrink-0">
                      <button
                        onClick={() => openEdit(l)}
                        className="p-1.5 rounded-lg hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
                      >
                        <Pencil className="h-3.5 w-3.5" />
                      </button>
                      <button
                        onClick={() => handleDelete(l)}
                        disabled={deletingId === l.id}
                        className="p-1.5 rounded-lg hover:bg-destructive/10 transition-colors text-muted-foreground hover:text-destructive"
                      >
                        {deletingId === l.id
                          ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                          : <Trash2 className="h-3.5 w-3.5" />}
                      </button>
                    </div>
                  </div>

                  {isExpanded && (
                    <div className="mt-4 pt-4 border-t border-border/30 space-y-2 text-sm">
                      {l.tenant_email && (
                        <div className="flex items-center gap-2 text-muted-foreground">
                          <Mail className="h-3.5 w-3.5 shrink-0" />
                          <a href={`mailto:${l.tenant_email}`} className="hover:text-foreground transition-colors">{l.tenant_email}</a>
                        </div>
                      )}
                      {l.deposit_amount != null && (
                        <div className="flex items-center gap-2 text-muted-foreground">
                          <DollarSign className="h-3.5 w-3.5 shrink-0" />
                          <span>Deposit: {formatMoney(l.deposit_amount, l.currency)} — {l.deposit_paid ? 'paid' : 'unpaid'}</span>
                        </div>
                      )}
                      {l.payment_day != null && (
                        <div className="flex items-center gap-2 text-muted-foreground">
                          <Calendar className="h-3.5 w-3.5 shrink-0" />
                          <span>Payment due on the {l.payment_day}th of each month</span>
                        </div>
                      )}
                      {l.end_date && days !== null && days >= 0 && (
                        <div className="flex items-center gap-2 text-muted-foreground">
                          <Calendar className="h-3.5 w-3.5 shrink-0" />
                          <span>{days} days remaining</span>
                        </div>
                      )}
                      {l.notes && (
                        <p className="text-muted-foreground text-xs mt-1">{l.notes}</p>
                      )}
                      {l.document_url && (
                        <a
                          href={l.document_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="inline-flex items-center gap-1 text-xs text-primary hover:underline mt-1"
                        >
                          <FileText className="h-3 w-3" />
                          View document
                          <ExternalLink className="h-3 w-3" />
                        </a>
                      )}

                      {/* Payment history */}
                      <PaymentHistory
                        lease={l}
                        payments={payments}
                        userId={userId}
                        propertyId={property.id}
                        onPaymentAdded={handlePaymentAdded}
                      />

                      <div className="pt-2 flex items-center gap-2 flex-wrap">
                        <Button
                          variant="ghost"
                          size="sm"
                          className="h-8 px-3 text-xs text-muted-foreground hover:text-foreground"
                          onClick={() => openAnalyse(l)}
                        >
                          <Sparkles className="h-3.5 w-3.5 mr-1" style={{ color: 'hsl(280,68%,57%)' }} />
                          Analyse lease
                        </Button>
                        {l.status !== 'terminated' && l.status !== 'expired' && (
                          <Button
                            variant="ghost"
                            size="sm"
                            className="text-destructive hover:text-destructive hover:bg-destructive/10 h-8 px-3 text-xs"
                            onClick={() => handleTerminate(l)}
                          >
                            Terminate lease
                          </Button>
                        )}
                      </div>
                    </div>
                  )}
                </Card>
              )
            })}
          </div>
        )}
      </div>

      {/* AI Lease Analysis modal */}
      {analyseLeaseId && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-lg p-5 space-y-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Sparkles className="h-4 w-4" style={{ color: 'hsl(280,68%,57%)' }} />
                <h2 className="font-semibold text-sm">AI Lease Analysis</h2>
              </div>
              <button onClick={closeAnalyse}>
                <X className="h-4 w-4 text-muted-foreground" />
              </button>
            </div>

            {!analysisResult ? (
              <div className="space-y-3">
                <p className="text-xs text-muted-foreground">Paste the lease text below and ARIA will extract key terms, red flags, and important dates.</p>
                <textarea
                  placeholder="Paste lease text here…"
                  value={leaseText}
                  onChange={(e) => setLeaseText(e.target.value)}
                  rows={8}
                  className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
                <div className="flex justify-end gap-2">
                  <Button type="button" variant="ghost" size="sm" onClick={closeAnalyse}>Cancel</Button>
                  <Button
                    size="sm"
                    disabled={!leaseText.trim() || analysing}
                    onClick={handleAnalyse}
                  >
                    {analysing
                      ? <><Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />Analysing…</>
                      : <><Sparkles className="h-3.5 w-3.5 mr-1" />Analyse</>
                    }
                  </Button>
                </div>
              </div>
            ) : (
              <div className="space-y-4 text-sm">
                <div className="rounded-xl border border-border/40 bg-muted/20 px-3 py-2.5">
                  <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-1">Summary</p>
                  <p className="text-sm text-foreground">{analysisResult.summary}</p>
                </div>

                {analysisResult.redFlags.length > 0 && (
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">⚠️ Red Flags</p>
                    <ul className="space-y-1">
                      {analysisResult.redFlags.map((flag, i) => (
                        <li key={i} className="flex items-start gap-1.5 text-xs text-destructive">
                          <AlertTriangle className="h-3.5 w-3.5 shrink-0 mt-0.5" />
                          {flag}
                        </li>
                      ))}
                    </ul>
                  </div>
                )}

                {analysisResult.obligations.length > 0 && (
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">Key Obligations</p>
                    <ul className="space-y-1">
                      {analysisResult.obligations.map((ob, i) => (
                        <li key={i} className="flex items-start gap-1.5 text-xs text-muted-foreground">
                          <span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-muted-foreground/60" />
                          {ob}
                        </li>
                      ))}
                    </ul>
                  </div>
                )}

                {analysisResult.importantDates.length > 0 && (
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">Important Dates</p>
                    <ul className="space-y-1">
                      {analysisResult.importantDates.map((d, i) => (
                        <li key={i} className="flex items-start gap-1.5 text-xs text-muted-foreground">
                          <Calendar className="h-3.5 w-3.5 shrink-0 mt-0.5" />
                          {d}
                        </li>
                      ))}
                    </ul>
                  </div>
                )}

                <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                  {analysisResult.rentEscalation && (
                    <div className="rounded-xl border border-border/40 bg-muted/20 px-3 py-2">
                      <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground mb-0.5">Rent Escalation</p>
                      <p className="text-xs text-foreground">{analysisResult.rentEscalation}</p>
                    </div>
                  )}
                  {analysisResult.depositConditions && (
                    <div className="rounded-xl border border-border/40 bg-muted/20 px-3 py-2">
                      <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground mb-0.5">Deposit Return</p>
                      <p className="text-xs text-foreground">{analysisResult.depositConditions}</p>
                    </div>
                  )}
                </div>

                <div className="flex justify-end gap-2 pt-1">
                  <Button variant="ghost" size="sm" onClick={() => setAnalysisResult(null)}>Re-analyse</Button>
                  <Button variant="ghost" size="sm" onClick={closeAnalyse}>Close</Button>
                </div>
              </div>
            )}
          </Card>
        </div>
      )}

      {/* Add/Edit modal */}
      {showForm && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-md p-5 space-y-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">{editId ? 'Edit Lease' : 'Add Lease'}</h2>
              <button onClick={() => setShowForm(false)}>
                <X className="h-4 w-4 text-muted-foreground" />
              </button>
            </div>
            <form onSubmit={handleSave} className="space-y-3">
              <Input
                placeholder="Tenant name *"
                value={form.tenant_name}
                onChange={(e) => setField('tenant_name', e.target.value)}
                required
              />
              <Input
                placeholder="Tenant email"
                type="email"
                value={form.tenant_email}
                onChange={(e) => setField('tenant_email', e.target.value)}
              />
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs text-muted-foreground">Start date *</label>
                  <Input
                    type="date"
                    value={form.start_date}
                    onChange={(e) => setField('start_date', e.target.value)}
                    required
                  />
                </div>
                <div>
                  <label className="text-xs text-muted-foreground">End date</label>
                  <Input
                    type="date"
                    value={form.end_date}
                    onChange={(e) => setField('end_date', e.target.value)}
                  />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <Input
                  placeholder="Monthly rent *"
                  type="number"
                  step="0.01"
                  min="0"
                  value={form.monthly_rent}
                  onChange={(e) => setField('monthly_rent', e.target.value)}
                  required
                />
                <Input
                  placeholder="Currency"
                  value={form.currency}
                  onChange={(e) => setField('currency', e.target.value)}
                />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <Input
                  placeholder="Deposit amount"
                  type="number"
                  step="0.01"
                  min="0"
                  value={form.deposit_amount}
                  onChange={(e) => setField('deposit_amount', e.target.value)}
                />
                <Input
                  placeholder="Payment day (1-28)"
                  type="number"
                  min="1"
                  max="28"
                  value={form.payment_day}
                  onChange={(e) => setField('payment_day', e.target.value)}
                />
              </div>
              <div className="flex items-center gap-2">
                <input
                  id="deposit-paid"
                  type="checkbox"
                  checked={form.deposit_paid}
                  onChange={(e) => setField('deposit_paid', e.target.checked)}
                  className="rounded"
                />
                <label htmlFor="deposit-paid" className="text-sm text-muted-foreground">Deposit paid</label>
              </div>
              <select
                value={form.status}
                onChange={(e) => setField('status', e.target.value as Lease['status'])}
                className={selectCls}
              >
                {(Object.keys(STATUS_CONFIG) as Lease['status'][]).map((s) => (
                  <option key={s} value={s}>{STATUS_CONFIG[s].label}</option>
                ))}
              </select>
              <Input
                placeholder="Document URL (optional)"
                value={form.document_url}
                onChange={(e) => setField('document_url', e.target.value)}
              />
              <textarea
                placeholder="Notes (optional)"
                value={form.notes}
                onChange={(e) => setField('notes', e.target.value)}
                rows={2}
                className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <div className="flex justify-end gap-2">
                <Button type="button" variant="ghost" size="sm" onClick={() => setShowForm(false)}>Cancel</Button>
                <Button type="submit" size="sm" disabled={saving}>
                  {saving && <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />}
                  {editId ? 'Save changes' : 'Add lease'}
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}
