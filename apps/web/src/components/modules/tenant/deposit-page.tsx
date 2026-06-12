'use client'

import * as React from 'react'
import {
  Vault, Plus, X, Loader2, Trash2, ChevronDown, ChevronUp,
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

interface Lease {
  id: string
  tenant_name: string
  deposit_amount: number | null
  deposit_paid: boolean | null
  currency: string | null
  status: string
}

interface Deduction {
  id: string
  property_id: string
  lease_id: string
  description: string
  amount: number
  currency: string | null
  deduction_date: string | null
  status: 'claimed' | 'disputed' | 'settled' | 'waived'
  notes: string | null
  created_by: string | null
  created_at: string
}

interface DepositPageProps {
  property: Property
  userId: string
  initialLeases: Lease[]
  initialDeductions: Deduction[]
}

const DEDUCTION_STATUS_CONFIG: Record<Deduction['status'], { label: string; color: string }> = {
  claimed:  { label: 'Claimed',  color: 'hsl(45,75%,42%)'  },
  disputed: { label: 'Disputed', color: 'hsl(0,68%,44%)'   },
  settled:  { label: 'Settled',  color: 'hsl(152,62%,38%)' },
  waived:   { label: 'Waived',   color: 'hsl(220,15%,50%)' },
}

function formatMoney(v: number | null | undefined, currency: string | null | undefined) {
  if (v == null) return '—'
  return `${v.toLocaleString('en', { maximumFractionDigits: 2 })} ${currency ?? ''}`.trim()
}

function formatDate(d: string | null) {
  if (!d) return '—'
  return new Date(d + 'T00:00:00').toLocaleDateString('en', { day: 'numeric', month: 'short', year: 'numeric' })
}

const EMPTY_FORM = {
  description: '',
  amount: '',
  currency: 'EUR',
  deduction_date: new Date().toISOString().slice(0, 10),
  status: 'claimed' as Deduction['status'],
  notes: '',
}

interface LeaseDeductionCardProps {
  lease: Lease
  deductions: Deduction[]
  userId: string
  propertyId: string
  onDeductionAdded: (d: Deduction) => void
  onDeductionUpdated: (d: Deduction) => void
  onDeductionDeleted: (id: string) => void
}

function LeaseDeductionCard({
  lease, deductions, userId, propertyId,
  onDeductionAdded, onDeductionUpdated, onDeductionDeleted,
}: LeaseDeductionCardProps) {
  const confirmDialog = useConfirm()
  const [expanded, setExpanded] = React.useState(false)
  const [showModal, setShowModal] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [updatingId, setUpdatingId] = React.useState<string | null>(null)
  const [form, setForm] = React.useState(EMPTY_FORM)

  const selectCls = 'w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30'

  const leaseDeductions = deductions.filter((d) => d.lease_id === lease.id)
  const totalSettled = leaseDeductions
    .filter((d) => d.status === 'settled')
    .reduce((sum, d) => sum + d.amount, 0)
  const totalAll = leaseDeductions.reduce((sum, d) => sum + d.amount, 0)
  const remaining = (lease.deposit_amount ?? 0) - totalSettled

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault()
    if (!form.description.trim() || !form.amount) return
    setSaving(true)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('deposit_deductions')
        .insert({
          property_id: propertyId,
          lease_id: lease.id,
          description: form.description.trim(),
          amount: parseFloat(form.amount),
          currency: form.currency || null,
          deduction_date: form.deduction_date || null,
          status: form.status,
          notes: form.notes.trim() || null,
          created_by: userId,
        })
        .select()
        .single()
      if (error) throw error
      onDeductionAdded(data as Deduction)
      setShowModal(false)
      setForm(EMPTY_FORM)
      toast({ title: 'Deduction added' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  async function updateStatus(d: Deduction, status: Deduction['status']) {
    setUpdatingId(d.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('deposit_deductions')
        .update({ status })
        .eq('id', d.id)
        .select()
        .single()
      if (error) throw error
      onDeductionUpdated(data as Deduction)
      toast({ title: 'Status updated' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setUpdatingId(null)
    }
  }

  async function handleDelete(d: Deduction) {
    const ok = await confirmDialog({
      title: 'Delete deduction',
      description: `Delete deduction "${d.description}"?`,
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(d.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('deposit_deductions').delete().eq('id', d.id)
      onDeductionDeleted(d.id)
      toast({ title: 'Deduction deleted' })
    } finally {
      setDeletingId(null)
    }
  }

  return (
    <Card className="p-4">
      <button
        className="flex items-start gap-3 w-full text-left"
        onClick={() => setExpanded(!expanded)}
      >
        <div
          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg mt-0.5"
          style={{ background: 'hsl(45,75%,42%)20', color: 'hsl(45,75%,42%)' }}
        >
          <Vault className="h-4 w-4" />
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 flex-wrap">
            <p className="font-semibold text-sm">{lease.tenant_name}</p>
            <Badge variant="neutral" style={{
              borderColor: lease.deposit_paid ? 'hsl(152,62%,38%)60' : 'hsl(0,68%,44%)60',
              color: lease.deposit_paid ? 'hsl(152,62%,38%)' : 'hsl(0,68%,44%)',
            }}>
              {lease.deposit_paid ? 'Paid' : 'Unpaid'}
            </Badge>
          </div>
          <p className="text-xs text-muted-foreground mt-0.5">
            Deposit: {formatMoney(lease.deposit_amount, lease.currency)}
            {leaseDeductions.length > 0 && (
              <> · Deductions: {formatMoney(totalAll, lease.currency)} · Remaining: {formatMoney(remaining, lease.currency)}</>
            )}
          </p>
        </div>
        <span className="text-muted-foreground mt-1">
          {expanded ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
        </span>
      </button>

      {expanded && (
        <div className="mt-4 pt-4 border-t border-border/30 space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Deductions</p>
            <Button variant="ghost" size="sm" className="h-7 px-2 text-xs" onClick={() => setShowModal(true)}>
              <Plus className="h-3 w-3 mr-1" />Add deduction
            </Button>
          </div>

          {leaseDeductions.length === 0 ? (
            <p className="text-xs text-muted-foreground py-2">No deductions yet</p>
          ) : (
            <div className="flex flex-col gap-2">
              {leaseDeductions.map((d) => {
                const cfg = DEDUCTION_STATUS_CONFIG[d.status]
                return (
                  <div key={d.id} className="flex items-start justify-between gap-2 rounded-xl border border-border/30 p-3">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2 flex-wrap">
                        <p className="text-sm font-medium">{d.description}</p>
                        <Badge variant="neutral" style={{ borderColor: cfg.color + '60', color: cfg.color }}>
                          {cfg.label}
                        </Badge>
                      </div>
                      <p className="text-xs text-muted-foreground mt-0.5">
                        {formatMoney(d.amount, d.currency)} · {formatDate(d.deduction_date)}
                      </p>
                      {d.notes && <p className="text-xs text-muted-foreground mt-1">{d.notes}</p>}
                      <div className="flex gap-1.5 flex-wrap mt-2">
                        {d.status === 'claimed' && (
                          <>
                            <button
                              onClick={() => updateStatus(d, 'disputed')}
                              disabled={updatingId === d.id}
                              className="text-[10px] px-2 py-0.5 rounded-full border border-destructive/40 text-destructive hover:bg-destructive/10 transition-colors"
                            >
                              Dispute
                            </button>
                            <button
                              onClick={() => updateStatus(d, 'settled')}
                              disabled={updatingId === d.id}
                              className="text-[10px] px-2 py-0.5 rounded-full border border-green-500/40 text-green-700 hover:bg-green-50 transition-colors"
                            >
                              Settle
                            </button>
                          </>
                        )}
                        {d.status === 'disputed' && (
                          <button
                            onClick={() => updateStatus(d, 'settled')}
                            disabled={updatingId === d.id}
                            className="text-[10px] px-2 py-0.5 rounded-full border border-green-500/40 text-green-700 hover:bg-green-50 transition-colors"
                          >
                            Settle
                          </button>
                        )}
                        {(d.status === 'settled' || d.status === 'claimed' || d.status === 'disputed') && (
                          <button
                            onClick={() => updateStatus(d, 'waived')}
                            disabled={updatingId === d.id}
                            className="text-[10px] px-2 py-0.5 rounded-full border border-muted text-muted-foreground hover:bg-muted transition-colors"
                          >
                            Waive
                          </button>
                        )}
                        {updatingId === d.id && <Loader2 className="h-3 w-3 animate-spin text-muted-foreground" />}
                      </div>
                    </div>
                    <button
                      onClick={() => handleDelete(d)}
                      disabled={deletingId === d.id}
                      className="p-1.5 rounded-lg hover:bg-destructive/10 transition-colors text-muted-foreground hover:text-destructive shrink-0"
                    >
                      {deletingId === d.id
                        ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                        : <Trash2 className="h-3.5 w-3.5" />}
                    </button>
                  </div>
                )
              })}
            </div>
          )}
        </div>
      )}

      {showModal && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-sm p-5 space-y-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold text-sm">Add Deduction</h2>
              <button onClick={() => setShowModal(false)}><X className="h-4 w-4 text-muted-foreground" /></button>
            </div>
            <form onSubmit={handleAdd} className="space-y-3">
              <Input
                placeholder="Description *"
                value={form.description}
                onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))}
                required
              />
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="text-xs text-muted-foreground">Amount *</label>
                  <Input
                    type="number"
                    step="0.01"
                    min="0"
                    placeholder="0.00"
                    value={form.amount}
                    onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))}
                    required
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
              <div>
                <label className="text-xs text-muted-foreground">Date</label>
                <Input
                  type="date"
                  value={form.deduction_date}
                  onChange={(e) => setForm((f) => ({ ...f, deduction_date: e.target.value }))}
                />
              </div>
              <div>
                <label className="text-xs text-muted-foreground">Status</label>
                <select
                  value={form.status}
                  onChange={(e) => setForm((f) => ({ ...f, status: e.target.value as Deduction['status'] }))}
                  className={selectCls}
                >
                  {(Object.keys(DEDUCTION_STATUS_CONFIG) as Deduction['status'][]).map((s) => (
                    <option key={s} value={s}>{DEDUCTION_STATUS_CONFIG[s].label}</option>
                  ))}
                </select>
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
                  Add deduction
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </Card>
  )
}

export function DepositPage({ property, userId, initialLeases, initialDeductions }: DepositPageProps) {
  const [deductions, setDeductions] = React.useState<Deduction[]>(initialDeductions)

  function handleDeductionAdded(d: Deduction) {
    setDeductions((prev) => [d, ...prev])
  }

  function handleDeductionUpdated(d: Deduction) {
    setDeductions((prev) => prev.map((x) => (x.id === d.id ? d : x)))
  }

  function handleDeductionDeleted(id: string) {
    setDeductions((prev) => prev.filter((x) => x.id !== id))
  }

  return (
    <>
      <PageHeader title="Deposit" description={property.name} backHref="/tenant" />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {initialLeases.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
            <Vault className="h-10 w-10 opacity-30" />
            <p className="text-sm">No leases with deposits yet</p>
            <p className="text-xs text-center max-w-xs">Add a lease with a deposit amount to track deductions here.</p>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {initialLeases.map((lease) => (
              <LeaseDeductionCard
                key={lease.id}
                lease={lease}
                deductions={deductions}
                userId={userId}
                propertyId={property.id}
                onDeductionAdded={handleDeductionAdded}
                onDeductionUpdated={handleDeductionUpdated}
                onDeductionDeleted={handleDeductionDeleted}
              />
            ))}
          </div>
        )}
      </div>
    </>
  )
}
