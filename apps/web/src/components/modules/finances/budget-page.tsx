'use client'

import * as React from 'react'
import { Plus, Pencil, Trash2, PiggyBank, AlertCircle, X } from 'lucide-react'
import type { Property, FinanceCategory } from '@/lib/supabase/types'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'

export interface CategoryBudget {
  id: string
  property_id: string
  category: string
  period: 'monthly' | 'annual'
  amount: number
  currency: string
  created_by: string | null
}

export interface SpendingRecord {
  category: string
  amount: number
}

interface BudgetPageProps {
  property: Property
  userId: string
  initialBudgets: CategoryBudget[]
  spendingRecords: SpendingRecord[]
}

const FINANCE_CATEGORIES: FinanceCategory[] = [
  'maintenance', 'utilities', 'insurance', 'mortgage', 'tax',
  'renovation', 'appliance', 'subscription', 'other',
]

const CATEGORY_COLORS: Record<FinanceCategory, string> = {
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

function aggregateSpending(records: SpendingRecord[]): Record<string, number> {
  const totals: Record<string, number> = {}
  for (const r of records) {
    totals[r.category] = (totals[r.category] ?? 0) + r.amount
  }
  return totals
}

function blankForm() {
  return {
    category: 'other' as FinanceCategory,
    period: 'monthly' as 'monthly' | 'annual',
    amount: '',
    currency: 'EUR',
  }
}

export function BudgetPage({ property, userId, initialBudgets, spendingRecords }: BudgetPageProps) {
  const confirmDialog = useConfirm()
  const [budgets, setBudgets] = React.useState<CategoryBudget[]>(initialBudgets)
  const [showModal, setShowModal] = React.useState(false)
  const [editingBudget, setEditingBudget] = React.useState<CategoryBudget | null>(null)
  const [submitting, setSubmitting] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [formError, setFormError] = React.useState<string | null>(null)

  // Form fields
  const [category, setCategory] = React.useState<FinanceCategory>('other')
  const [period, setPeriod] = React.useState<'monthly' | 'annual'>('monthly')
  const [amount, setAmount] = React.useState('')
  const [currency, setCurrency] = React.useState('EUR')

  const spending = React.useMemo(() => aggregateSpending(spendingRecords), [spendingRecords])

  const totalBudgeted = budgets.reduce((s, b) => {
    // Normalize annual budgets to monthly equivalent for comparison
    return s + (b.period === 'annual' ? b.amount / 12 : b.amount)
  }, 0)

  const totalSpent = Object.values(spending).reduce((s, v) => s + v, 0)

  function openAdd() {
    setEditingBudget(null)
    const f = blankForm()
    setCategory(f.category)
    setPeriod(f.period)
    setAmount(f.amount)
    setCurrency(f.currency)
    setFormError(null)
    setShowModal(true)
  }

  function openEdit(budget: CategoryBudget) {
    setEditingBudget(budget)
    setCategory(budget.category as FinanceCategory)
    setPeriod(budget.period)
    setAmount(String(budget.amount))
    setCurrency(budget.currency)
    setFormError(null)
    setShowModal(true)
  }

  function closeModal() {
    setShowModal(false)
    setEditingBudget(null)
    setFormError(null)
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!amount || parseFloat(amount) <= 0) return
    setSubmitting(true)
    setFormError(null)

    const supabase = createClient()
    const payload = {
      category,
      period,
      amount: parseFloat(amount),
      currency,
    }

    if (editingBudget) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: updated, error } = await (supabase as any)
        .from('category_budgets')
        .update(payload)
        .eq('id', editingBudget.id)
        .select()
        .single()

      if (error) {
        setFormError((error as { message: string }).message ?? 'Failed to update budget')
        setSubmitting(false)
        return
      }
      setBudgets((prev) => prev.map((b) => (b.id === editingBudget.id ? (updated as CategoryBudget) : b)))
    } else {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: inserted, error } = await (supabase as any)
        .from('category_budgets')
        .insert({ ...payload, property_id: property.id, created_by: userId })
        .select()
        .single()

      if (error) {
        setFormError((error as { message: string }).message ?? 'Failed to create budget')
        setSubmitting(false)
        return
      }
      setBudgets((prev) => [...prev, inserted as CategoryBudget])
    }

    setSubmitting(false)
    closeModal()
  }

  async function handleDelete(budget: CategoryBudget) {
    const ok = await confirmDialog({
      title: `Delete ${budget.category} budget?`,
      description: `This will remove the ${budget.period} budget of ${budget.currency} ${budget.amount.toLocaleString()} for ${budget.category}.`,
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(budget.id)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error } = await (supabase as any).from('category_budgets').delete().eq('id', budget.id)
    if (error) {
      toast({ title: 'Error', description: 'Failed to delete budget', variant: 'destructive' })
    } else {
      setBudgets((prev) => prev.filter((b) => b.id !== budget.id))
    }
    setDeletingId(null)
  }

  const now = new Date()
  const monthLabel = now.toLocaleString('en-US', { month: 'long', year: 'numeric' })

  return (
    <>
      <PageHeader
        title="Budget"
        description={property.name}
        backHref="/finances"
        action={{ label: 'Set budget', href: '#', onClick: openAdd }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6">

        {/* Summary card */}
        <div className="grid grid-cols-2 gap-3">
          <Card variant="default" padding="sm">
            <div className="flex items-center gap-2 mb-1">
              <PiggyBank className="h-4 w-4 text-[hsl(220,62%,60%)]" />
              <p className="text-xs text-muted-foreground">Monthly budget</p>
            </div>
            <p className="text-xl font-bold text-[hsl(220,62%,60%)]">
              €{Math.round(totalBudgeted).toLocaleString()}
            </p>
          </Card>
          <Card variant="default" padding="sm">
            <div className="flex items-center gap-2 mb-1">
              <div className="h-4 w-4 rounded-sm bg-destructive/60" />
              <p className="text-xs text-muted-foreground">Spent this month</p>
            </div>
            <p className={cn('text-xl font-bold', totalSpent > totalBudgeted && totalBudgeted > 0 ? 'text-destructive' : 'text-foreground')}>
              €{Math.round(totalSpent).toLocaleString()}
            </p>
          </Card>
        </div>

        {/* Budget list */}
        {budgets.length === 0 ? (
          <EmptyState onAdd={openAdd} />
        ) : (
          <div className="flex flex-col gap-3">
            <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              {monthLabel} — spending vs budget
            </p>
            {budgets.map((budget) => {
              const monthlyBudget = budget.period === 'annual' ? budget.amount / 12 : budget.amount
              const spent = spending[budget.category] ?? 0
              const pct = monthlyBudget > 0 ? (spent / monthlyBudget) * 100 : 0
              const remaining = monthlyBudget - spent
              const isOver = pct > 100
              const isWarn = pct > 80
              const color = CATEGORY_COLORS[budget.category as FinanceCategory] ?? 'hsl(0,0%,50%)'
              const barColor = isOver
                ? 'hsl(0,68%,52%)'
                : isWarn
                  ? 'hsl(45,75%,52%)'
                  : color
              const displayPct = Math.min(pct, 100)

              return (
                <Card
                  key={budget.id}
                  variant="default"
                  padding="md"
                  className="cursor-pointer hover:ring-1 hover:ring-primary/20 transition-all"
                  onClick={() => openEdit(budget)}
                >
                  <div className="flex items-start gap-3">
                    <div
                      className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl"
                      style={{ background: `${color}18`, border: `1px solid ${color}30` }}
                    >
                      <PiggyBank className="h-4.5 w-4.5" style={{ color }} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between gap-2 mb-0.5">
                        <div className="flex items-center gap-2">
                          <span className="text-sm font-medium text-foreground capitalize">{budget.category}</span>
                          <Badge
                            variant="neutral"
                            size="xs"
                            className="text-[10px]"
                            style={{ color, borderColor: `${color}44`, background: `${color}18` }}
                          >
                            {budget.period}
                          </Badge>
                        </div>
                        <div className="flex items-center gap-1">
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 shrink-0"
                            aria-label="Edit budget"
                            onClick={(e) => { e.stopPropagation(); openEdit(budget) }}
                          >
                            <Pencil className="h-3.5 w-3.5 text-muted-foreground" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 shrink-0"
                            aria-label="Delete budget"
                            loading={deletingId === budget.id}
                            onClick={(e) => { e.stopPropagation(); void handleDelete(budget) }}
                          >
                            <Trash2 className="h-3.5 w-3.5 text-destructive" />
                          </Button>
                        </div>
                      </div>

                      {/* Amount row */}
                      <div className="flex items-center justify-between mb-2">
                        <span className="text-xs text-muted-foreground">
                          <span className={cn('font-medium tabular-nums', isOver ? 'text-destructive' : 'text-foreground')}>
                            {budget.currency} {Math.round(spent).toLocaleString()}
                          </span>
                          {' '}
                          <span className="text-muted-foreground">
                            / {budget.currency} {Math.round(monthlyBudget).toLocaleString()} /mo
                            {budget.period === 'annual' && (
                              <span className="ml-1 text-[10px] opacity-70">(÷12)</span>
                            )}
                          </span>
                        </span>
                        <span className={cn(
                          'text-xs font-semibold tabular-nums',
                          isOver ? 'text-destructive' : isWarn ? 'text-[hsl(45,75%,52%)]' : 'text-[hsl(152,62%,48%)]'
                        )}>
                          {isOver
                            ? `${budget.currency} ${Math.round(Math.abs(remaining)).toLocaleString()} over`
                            : `${budget.currency} ${Math.round(remaining).toLocaleString()} left`
                          }
                        </span>
                      </div>

                      {/* Progress bar */}
                      <div
                        className="h-2 rounded-full overflow-hidden"
                        style={{ background: `${color}14` }}
                      >
                        <div
                          className="h-full rounded-full transition-all duration-500"
                          style={{
                            width: `${displayPct}%`,
                            background: barColor,
                          }}
                        />
                      </div>
                      {isOver && (
                        <p className="mt-1.5 text-[10px] font-medium text-destructive">
                          Over budget by {Math.round(pct - 100)}%
                        </p>
                      )}
                    </div>
                  </div>
                </Card>
              )
            })}

            {/* Total summary row */}
            {budgets.length > 1 && (
              <Card variant="default" padding="sm">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Total</span>
                  <div className="flex items-center gap-3">
                    <span className="text-xs text-muted-foreground">
                      <span className={cn('font-bold tabular-nums', totalSpent > totalBudgeted && totalBudgeted > 0 ? 'text-destructive' : 'text-foreground')}>
                        €{Math.round(totalSpent).toLocaleString()}
                      </span>
                      {' / '}
                      <span className="text-[hsl(220,62%,60%)] font-bold tabular-nums">
                        €{Math.round(totalBudgeted).toLocaleString()}
                      </span>
                      <span className="text-muted-foreground"> /mo</span>
                    </span>
                    {totalBudgeted > 0 && (
                      <span className={cn(
                        'text-xs font-bold',
                        totalSpent > totalBudgeted ? 'text-destructive' : totalSpent / totalBudgeted > 0.8 ? 'text-[hsl(45,75%,52%)]' : 'text-[hsl(152,62%,48%)]'
                      )}>
                        {Math.round((totalSpent / totalBudgeted) * 100)}%
                      </span>
                    )}
                  </div>
                </div>
              </Card>
            )}
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
                {editingBudget ? 'Edit budget' : 'Set budget'}
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
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  Category
                </label>
                <select
                  value={category}
                  onChange={(e) => setCategory(e.target.value as FinanceCategory)}
                  className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 capitalize"
                >
                  {FINANCE_CATEGORIES.map((c) => (
                    <option key={c} value={c} className="capitalize">{c}</option>
                  ))}
                </select>
              </div>

              <div className="flex flex-col gap-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  Period
                </label>
                <div className="flex gap-2">
                  {(['monthly', 'annual'] as const).map((p) => (
                    <button
                      key={p}
                      type="button"
                      onClick={() => setPeriod(p)}
                      className={cn(
                        'flex-1 rounded-xl py-2 text-xs font-medium transition-colors border capitalize',
                        period === p
                          ? 'bg-primary/20 text-primary border-primary/30'
                          : 'glass-light text-muted-foreground hover:text-foreground border-transparent'
                      )}
                    >
                      {p}
                    </button>
                  ))}
                </div>
              </div>

              <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
                <div className="flex flex-col gap-2 col-span-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                    Amount *
                  </label>
                  <input
                    type="number"
                    value={amount}
                    onChange={(e) => setAmount(e.target.value)}
                    placeholder="0.00"
                    min="0.01"
                    step="0.01"
                    required
                    inputMode="decimal"
                    className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  />
                </div>
                <div className="flex flex-col gap-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                    Currency
                  </label>
                  <input
                    value={currency}
                    onChange={(e) => setCurrency(e.target.value.toUpperCase())}
                    placeholder="EUR"
                    maxLength={3}
                    className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 uppercase"
                  />
                </div>
              </div>

              <Button
                type="submit"
                size="sm"
                loading={submitting}
                disabled={!amount || parseFloat(amount) <= 0}
              >
                {editingBudget ? 'Update budget' : 'Save budget'}
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
        <PiggyBank className="h-7 w-7 text-muted-foreground" />
      </div>
      <p className="font-semibold text-foreground">No budgets set</p>
      <p className="text-sm text-muted-foreground max-w-[200px]">
        Set monthly or annual spending limits per category to track your property costs
      </p>
      <Button variant="secondary" size="sm" onClick={onAdd}>
        <Plus className="h-3.5 w-3.5" />
        Set your first budget
      </Button>
    </div>
  )
}
