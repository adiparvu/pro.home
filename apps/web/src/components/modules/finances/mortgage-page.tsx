'use client'

import * as React from 'react'
import { Plus, Pencil, Trash2, Building2, X, AlertCircle, ChevronDown, ChevronUp } from 'lucide-react'
import type { Property } from '@/lib/supabase/types'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'

export interface Mortgage {
  id: string
  property_id: string
  lender: string
  loan_amount: number
  current_balance: number | null
  interest_rate: number
  monthly_payment: number
  start_date: string
  end_date: string | null
  loan_type: 'repayment' | 'interest-only' | 'fixed' | null
  currency: string
  notes: string | null
  created_by: string | null
  created_at: string
}

interface MortgagePageProps {
  property: Property
  userId: string
  initialMortgages: Mortgage[]
}

const LOAN_TYPE_OPTIONS = ['repayment', 'interest-only', 'fixed'] as const
type LoanType = typeof LOAN_TYPE_OPTIONS[number]

const LOAN_TYPE_COLORS: Record<LoanType, string> = {
  'repayment': 'hsl(270,62%,52%)',
  'interest-only': 'hsl(22,68%,45%)',
  'fixed': 'hsl(220,62%,52%)',
}

function blankForm() {
  return {
    lender: '',
    loan_amount: '',
    current_balance: '',
    interest_rate: '',
    monthly_payment: '',
    start_date: '',
    end_date: '',
    loan_type: 'repayment' as LoanType,
    currency: 'EUR',
    notes: '',
  }
}

export function MortgagePage({ property, userId, initialMortgages }: MortgagePageProps) {
  const confirmDialog = useConfirm()
  const [mortgages, setMortgages] = React.useState<Mortgage[]>(initialMortgages)
  const [showModal, setShowModal] = React.useState(false)
  const [editingMortgage, setEditingMortgage] = React.useState<Mortgage | null>(null)
  const [submitting, setSubmitting] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [formError, setFormError] = React.useState<string | null>(null)
  const [expandedIds, setExpandedIds] = React.useState<Set<string>>(new Set())

  const [lender, setLender] = React.useState('')
  const [loanAmount, setLoanAmount] = React.useState('')
  const [currentBalance, setCurrentBalance] = React.useState('')
  const [interestRate, setInterestRate] = React.useState('')
  const [monthlyPayment, setMonthlyPayment] = React.useState('')
  const [startDate, setStartDate] = React.useState('')
  const [endDate, setEndDate] = React.useState('')
  const [loanType, setLoanType] = React.useState<LoanType>('repayment')
  const [currency, setCurrency] = React.useState('EUR')
  const [notes, setNotes] = React.useState('')

  const totalMonthlyPayments = mortgages.reduce((s, m) => s + m.monthly_payment, 0)

  function openAdd() {
    setEditingMortgage(null)
    const f = blankForm()
    setLender(f.lender)
    setLoanAmount(f.loan_amount)
    setCurrentBalance(f.current_balance)
    setInterestRate(f.interest_rate)
    setMonthlyPayment(f.monthly_payment)
    setStartDate(f.start_date)
    setEndDate(f.end_date)
    setLoanType(f.loan_type)
    setCurrency(f.currency)
    setNotes(f.notes)
    setFormError(null)
    setShowModal(true)
  }

  function openEdit(m: Mortgage) {
    setEditingMortgage(m)
    setLender(m.lender)
    setLoanAmount(String(m.loan_amount))
    setCurrentBalance(m.current_balance != null ? String(m.current_balance) : '')
    setInterestRate(String(m.interest_rate))
    setMonthlyPayment(String(m.monthly_payment))
    setStartDate(m.start_date)
    setEndDate(m.end_date ?? '')
    setLoanType((m.loan_type as LoanType) ?? 'repayment')
    setCurrency(m.currency)
    setNotes(m.notes ?? '')
    setFormError(null)
    setShowModal(true)
  }

  function closeModal() {
    setShowModal(false)
    setEditingMortgage(null)
    setFormError(null)
  }

  function toggleExpand(id: string) {
    setExpandedIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!lender.trim() || !loanAmount || !interestRate || !monthlyPayment || !startDate) return
    setSubmitting(true)
    setFormError(null)

    const supabase = createClient()
    const payload = {
      lender: lender.trim(),
      loan_amount: parseFloat(loanAmount),
      current_balance: currentBalance ? parseFloat(currentBalance) : null,
      interest_rate: parseFloat(interestRate),
      monthly_payment: parseFloat(monthlyPayment),
      start_date: startDate,
      end_date: endDate || null,
      loan_type: loanType,
      currency,
      notes: notes.trim() || null,
    }

    if (editingMortgage) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: updated, error } = await (supabase as any)
        .from('mortgages')
        .update(payload)
        .eq('id', editingMortgage.id)
        .select()
        .single()

      if (error) {
        setFormError((error as { message: string }).message ?? 'Failed to update mortgage')
        setSubmitting(false)
        return
      }
      setMortgages((prev) => prev.map((m) => (m.id === editingMortgage.id ? (updated as Mortgage) : m)))
    } else {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: inserted, error } = await (supabase as any)
        .from('mortgages')
        .insert({ ...payload, property_id: property.id, created_by: userId })
        .select()
        .single()

      if (error) {
        setFormError((error as { message: string }).message ?? 'Failed to add mortgage')
        setSubmitting(false)
        return
      }
      setMortgages((prev) => [inserted as Mortgage, ...prev])
    }

    setSubmitting(false)
    closeModal()
  }

  async function handleDelete(m: Mortgage) {
    const ok = await confirmDialog({
      title: `Delete ${m.lender} mortgage?`,
      description: `This will permanently remove the ${m.currency} ${m.loan_amount.toLocaleString()} mortgage from ${m.lender}.`,
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(m.id)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error } = await (supabase as any).from('mortgages').delete().eq('id', m.id)
    if (error) {
      toast({ title: 'Error', description: 'Failed to delete mortgage', variant: 'destructive' })
    } else {
      setMortgages((prev) => prev.filter((x) => x.id !== m.id))
    }
    setDeletingId(null)
  }

  return (
    <>
      <PageHeader
        title="Mortgage"
        description={property.name}
        action={{ label: 'Add mortgage', href: '#', onClick: openAdd }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6">

        {/* Summary card */}
        <Card variant="default" padding="sm">
          <div className="flex items-center gap-2 mb-1">
            <Building2 className="h-4 w-4 text-[hsl(270,62%,60%)]" />
            <p className="text-xs text-muted-foreground">Total monthly payments</p>
          </div>
          <p className="text-xl font-bold text-[hsl(270,62%,60%)]">
            €{Math.round(totalMonthlyPayments).toLocaleString()}
            <span className="text-sm font-normal text-muted-foreground ml-1">/mo</span>
          </p>
        </Card>

        {mortgages.length === 0 ? (
          <EmptyState onAdd={openAdd} />
        ) : (
          <div className="flex flex-col gap-3">
            {mortgages.map((m) => {
              const balance = m.current_balance ?? m.loan_amount
              const paid = m.loan_amount - balance
              const pctPaid = m.loan_amount > 0 ? Math.max(0, Math.min(100, (paid / m.loan_amount) * 100)) : 0
              const color = LOAN_TYPE_COLORS[(m.loan_type as LoanType) ?? 'repayment'] ?? 'hsl(270,62%,52%)'
              const isExpanded = expandedIds.has(m.id)

              return (
                <Card key={m.id} variant="default" padding="md">
                  <div className="flex items-start gap-3">
                    <div
                      className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl"
                      style={{ background: `${color}18`, border: `1px solid ${color}30` }}
                    >
                      <Building2 className="h-4.5 w-4.5" style={{ color }} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between gap-2 mb-0.5">
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className="text-sm font-semibold text-foreground">{m.lender}</span>
                          {m.loan_type && (
                            <Badge
                              variant="neutral"
                              size="xs"
                              className="text-[10px] capitalize"
                              style={{ color, borderColor: `${color}44`, background: `${color}18` }}
                            >
                              {m.loan_type}
                            </Badge>
                          )}
                        </div>
                        <div className="flex items-center gap-1">
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 shrink-0"
                            aria-label="Edit mortgage"
                            onClick={() => openEdit(m)}
                          >
                            <Pencil className="h-3.5 w-3.5 text-muted-foreground" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 shrink-0"
                            aria-label="Delete mortgage"
                            loading={deletingId === m.id}
                            onClick={() => { void handleDelete(m) }}
                          >
                            <Trash2 className="h-3.5 w-3.5 text-destructive" />
                          </Button>
                        </div>
                      </div>

                      {/* Amounts */}
                      <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 my-2">
                        <div>
                          <p className="text-[10px] text-muted-foreground uppercase tracking-wider">Loan amount</p>
                          <p className="text-sm font-semibold tabular-nums">{m.currency} {m.loan_amount.toLocaleString()}</p>
                        </div>
                        <div>
                          <p className="text-[10px] text-muted-foreground uppercase tracking-wider">Balance</p>
                          <p className="text-sm font-semibold tabular-nums">{m.currency} {balance.toLocaleString()}</p>
                        </div>
                        <div>
                          <p className="text-[10px] text-muted-foreground uppercase tracking-wider">Monthly</p>
                          <p className="text-sm font-semibold tabular-nums text-[hsl(270,62%,60%)]">{m.currency} {m.monthly_payment.toLocaleString()}</p>
                        </div>
                      </div>

                      {/* Interest rate */}
                      <p className="text-xs text-muted-foreground mb-2">
                        Interest rate: <span className="font-medium text-foreground">{m.interest_rate}%</span>
                        {m.start_date && (
                          <span className="ml-2">
                            · {new Date(m.start_date).getFullYear()}
                            {m.end_date ? ` – ${new Date(m.end_date).getFullYear()}` : ''}
                          </span>
                        )}
                      </p>

                      {/* Progress bar */}
                      <div className="mb-1">
                        <div className="flex items-center justify-between mb-1">
                          <span className="text-[10px] text-muted-foreground">Paid off</span>
                          <span className="text-[10px] font-semibold text-foreground">{pctPaid.toFixed(1)}%</span>
                        </div>
                        <div className="h-2 rounded-full overflow-hidden" style={{ background: `${color}14` }}>
                          <div
                            className="h-full rounded-full transition-all duration-500"
                            style={{ width: `${pctPaid}%`, background: color }}
                          />
                        </div>
                      </div>

                      {/* Expand/collapse notes */}
                      {m.notes && (
                        <button
                          type="button"
                          className="flex items-center gap-1 mt-2 text-[10px] text-muted-foreground hover:text-foreground transition-colors"
                          onClick={() => toggleExpand(m.id)}
                        >
                          {isExpanded ? <ChevronUp className="h-3 w-3" /> : <ChevronDown className="h-3 w-3" />}
                          {isExpanded ? 'Hide notes' : 'Show notes'}
                        </button>
                      )}
                      {isExpanded && m.notes && (
                        <p className="mt-1.5 text-xs text-muted-foreground bg-muted/30 rounded-lg px-3 py-2">{m.notes}</p>
                      )}
                    </div>
                  </div>
                </Card>
              )
            })}
          </div>
        )}
      </div>

      {/* Modal */}
      {showModal && (
        <div
          className="fixed inset-0 z-50 flex items-end md:items-center justify-center bg-black/40 backdrop-blur-sm px-4 pb-4 md:pb-0"
          onClick={(e) => { if (e.target === e.currentTarget) closeModal() }}
        >
          <Card variant="default" padding="md" className="w-full max-w-sm max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between mb-4">
              <p className="text-sm font-semibold text-foreground">
                {editingMortgage ? 'Edit mortgage' : 'Add mortgage'}
              </p>
              <button
                type="button"
                onClick={closeModal}
                className="flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground hover:text-foreground transition-colors"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <form onSubmit={(e) => { void handleSubmit(e) }} className="flex flex-col gap-4">
              {formError && (
                <div className="flex items-center gap-2 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2">
                  <AlertCircle className="h-3.5 w-3.5 text-destructive shrink-0" />
                  <p className="text-xs text-destructive">{formError}</p>
                </div>
              )}

              <div className="flex flex-col gap-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Lender *</label>
                <input
                  value={lender}
                  onChange={(e) => setLender(e.target.value)}
                  placeholder="e.g. Halifax, Barclays"
                  required
                  className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="flex flex-col gap-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Loan amount *</label>
                  <input
                    type="number"
                    value={loanAmount}
                    onChange={(e) => setLoanAmount(e.target.value)}
                    placeholder="200000"
                    min="0"
                    step="0.01"
                    required
                    inputMode="decimal"
                    className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  />
                </div>
                <div className="flex flex-col gap-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Current balance</label>
                  <input
                    type="number"
                    value={currentBalance}
                    onChange={(e) => setCurrentBalance(e.target.value)}
                    placeholder="180000"
                    min="0"
                    step="0.01"
                    inputMode="decimal"
                    className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="flex flex-col gap-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Interest rate % *</label>
                  <input
                    type="number"
                    value={interestRate}
                    onChange={(e) => setInterestRate(e.target.value)}
                    placeholder="3.5"
                    min="0"
                    step="0.01"
                    required
                    inputMode="decimal"
                    className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  />
                </div>
                <div className="flex flex-col gap-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Monthly payment *</label>
                  <input
                    type="number"
                    value={monthlyPayment}
                    onChange={(e) => setMonthlyPayment(e.target.value)}
                    placeholder="950"
                    min="0"
                    step="0.01"
                    required
                    inputMode="decimal"
                    className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="flex flex-col gap-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Start date *</label>
                  <input
                    type="date"
                    value={startDate}
                    onChange={(e) => setStartDate(e.target.value)}
                    required
                    className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  />
                </div>
                <div className="flex flex-col gap-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">End date</label>
                  <input
                    type="date"
                    value={endDate}
                    onChange={(e) => setEndDate(e.target.value)}
                    className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  />
                </div>
              </div>

              <div className="flex flex-col gap-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Loan type</label>
                <div className="flex gap-2">
                  {LOAN_TYPE_OPTIONS.map((t) => (
                    <button
                      key={t}
                      type="button"
                      onClick={() => setLoanType(t)}
                      className={cn(
                        'flex-1 rounded-xl py-2 text-xs font-medium transition-colors border capitalize',
                        loanType === t
                          ? 'bg-primary/20 text-primary border-primary/30'
                          : 'glass-light text-muted-foreground hover:text-foreground border-transparent'
                      )}
                    >
                      {t}
                    </button>
                  ))}
                </div>
              </div>

              <div className="flex flex-col gap-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Currency</label>
                <input
                  value={currency}
                  onChange={(e) => setCurrency(e.target.value.toUpperCase())}
                  placeholder="EUR"
                  maxLength={3}
                  className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 uppercase"
                />
              </div>

              <div className="flex flex-col gap-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Notes</label>
                <textarea
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  placeholder="Any additional notes..."
                  rows={3}
                  className="w-full rounded-xl border border-border glass-light px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 resize-none"
                />
              </div>

              <Button
                type="submit"
                size="sm"
                loading={submitting}
                disabled={!lender.trim() || !loanAmount || !interestRate || !monthlyPayment || !startDate}
              >
                {editingMortgage ? 'Update mortgage' : 'Add mortgage'}
              </Button>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}

function EmptyState({ onAdd }: { onAdd: () => void }) {
  return (
    <div className="flex flex-col items-center gap-3 py-16 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-2xl glass-standard">
        <Building2 className="h-7 w-7 text-muted-foreground" />
      </div>
      <p className="font-semibold text-foreground">No mortgages tracked</p>
      <p className="text-sm text-muted-foreground max-w-[200px]">
        Track your mortgage details, repayment progress and monthly payments
      </p>
      <Button variant="secondary" size="sm" onClick={onAdd}>
        <Plus className="h-3.5 w-3.5" />
        Add your first mortgage
      </Button>
    </div>
  )
}
