'use client'

import * as React from 'react'
import { DollarSign, TrendingDown, TrendingUp, Plus, Trash2, ChevronDown, ChevronUp, AlertCircle } from 'lucide-react'
import type { Property, FinancialRecord, FinanceCategory, FinanceType } from '@/lib/supabase/types'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'

interface FinancesPageProps {
  property: Property
  userId: string
  initialRecords: FinancialRecord[]
}

const EXPENSE_CATEGORIES: FinanceCategory[] = [
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

export function FinancesPage({ property, userId, initialRecords }: FinancesPageProps) {
  const [records, setRecords] = React.useState<FinancialRecord[]>(initialRecords)
  const [typeFilter, setTypeFilter] = React.useState<FinanceType | 'all'>('all')
  const [showForm, setShowForm] = React.useState(false)
  const [submitting, setSubmitting] = React.useState(false)
  const [formError, setFormError] = React.useState<string | null>(null)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)

  const [title, setTitle] = React.useState('')
  const [amount, setAmount] = React.useState('')
  const [type, setType] = React.useState<FinanceType>('expense')
  const [category, setCategory] = React.useState<FinanceCategory>('other')
  const [date, setDate] = React.useState(new Date().toISOString().split('T')[0])
  const [description, setDescription] = React.useState('')

  const filtered = typeFilter === 'all' ? records : records.filter((r) => r.type === typeFilter)

  const totalExpenses = records.filter((r) => r.type === 'expense').reduce((s, r) => s + r.amount, 0)
  const totalIncome = records.filter((r) => r.type === 'income').reduce((s, r) => s + r.amount, 0)
  const balance = totalIncome - totalExpenses

  const currentYear = new Date().getFullYear()
  const ytdExpenses = records
    .filter((r) => r.type === 'expense' && new Date(r.date).getFullYear() === currentYear)
    .reduce((s, r) => s + r.amount, 0)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!title.trim() || !amount) return
    setSubmitting(true)
    setFormError(null)

    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: record, error } = await (supabase as any)
      .from('financial_records')
      .insert({
        property_id: property.id,
        title: title.trim(),
        amount: parseFloat(amount),
        currency: 'EUR',
        type,
        category,
        date,
        description: description.trim() || null,
        tags: [],
        created_by: userId,
      })
      .select()
      .single()

    if (error) {
      setFormError((error as { message: string }).message ?? 'Failed to save record')
      setSubmitting(false)
      return
    }

    setRecords((prev) => [record as FinancialRecord, ...prev].sort((a, b) => b.date.localeCompare(a.date)))
    setShowForm(false)
    setTitle('')
    setAmount('')
    setDescription('')
    setType('expense')
    setCategory('other')
    setDate(new Date().toISOString().split('T')[0])
    setSubmitting(false)
  }

  async function handleDelete(record: FinancialRecord) {
    if (!confirm(`Delete "${record.title}"?`)) return
    setDeletingId(record.id)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('financial_records').delete().eq('id', record.id)
    setRecords((prev) => prev.filter((r) => r.id !== record.id))
    setDeletingId(null)
  }

  return (
    <>
      <PageHeader title="Finances" description={property.name} />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Summary cards */}
        <div className="grid grid-cols-2 gap-3">
          <Card variant="default" padding="sm">
            <div className="flex items-center gap-2 mb-1">
              <TrendingDown className="h-4 w-4 text-destructive" />
              <p className="text-xs text-muted-foreground">YTD Expenses</p>
            </div>
            <p className="text-xl font-bold text-destructive">€{ytdExpenses.toLocaleString()}</p>
          </Card>
          <Card variant="default" padding="sm">
            <div className="flex items-center gap-2 mb-1">
              <DollarSign className="h-4 w-4 text-muted-foreground" />
              <p className="text-xs text-muted-foreground">Net Balance</p>
            </div>
            <p className={`text-xl font-bold ${balance >= 0 ? 'text-[hsl(152,62%,48%)]' : 'text-destructive'}`}>
              {balance >= 0 ? '+' : ''}€{Math.abs(balance).toLocaleString()}
            </p>
          </Card>
        </div>

        {/* Add record toggle */}
        <Button
          variant="secondary"
          size="sm"
          onClick={() => setShowForm((v) => !v)}
          className="self-start"
        >
          <Plus className="h-3.5 w-3.5" />
          {showForm ? 'Cancel' : 'Log expense / income'}
          {showForm ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
        </Button>

        {/* Add record form */}
        {showForm && (
          <Card variant="default" padding="md">
            <form onSubmit={handleSubmit} className="flex flex-col gap-4">
              {formError && (
                <div className="flex items-center gap-2 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2">
                  <AlertCircle className="h-3.5 w-3.5 text-destructive shrink-0" />
                  <p className="text-xs text-destructive">{formError}</p>
                </div>
              )}

              {/* Type toggle */}
              <div className="flex gap-2">
                {(['expense', 'income'] as FinanceType[]).map((t) => (
                  <button
                    key={t}
                    type="button"
                    onClick={() => setType(t)}
                    className={`flex-1 rounded-xl py-2 text-sm font-medium transition-colors capitalize ${
                      type === t
                        ? t === 'expense'
                          ? 'bg-destructive/20 text-destructive border border-destructive/30'
                          : 'bg-[hsl(152,62%,42%)]/20 text-[hsl(152,62%,48%)] border border-[hsl(152,62%,42%)]/30'
                        : 'glass-light text-muted-foreground hover:text-foreground'
                    }`}
                  >
                    {t}
                  </button>
                ))}
              </div>

              <div className="flex flex-col gap-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Title *</label>
                <input
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder='e.g. "Plumber visit", "Rent received"'
                  required
                  className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="flex flex-col gap-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Amount (€) *</label>
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
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Date</label>
                  <input
                    type="date"
                    value={date}
                    onChange={(e) => setDate(e.target.value)}
                    className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  />
                </div>
              </div>

              <div className="flex flex-col gap-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Category</label>
                <select
                  value={category}
                  onChange={(e) => setCategory(e.target.value as FinanceCategory)}
                  className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 capitalize"
                >
                  {EXPENSE_CATEGORIES.map((c) => (
                    <option key={c} value={c} className="capitalize">{c}</option>
                  ))}
                </select>
              </div>

              <div className="flex flex-col gap-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Notes</label>
                <input
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  placeholder="Optional"
                  className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                />
              </div>

              <Button type="submit" size="sm" loading={submitting} disabled={!title.trim() || !amount}>
                Save record
              </Button>
            </form>
          </Card>
        )}

        {/* Filter tabs */}
        {records.length > 0 && (
          <div className="flex gap-2">
            {(['all', 'expense', 'income'] as const).map((t) => (
              <button
                key={t}
                type="button"
                onClick={() => setTypeFilter(t)}
                className={`shrink-0 rounded-full px-3 py-1 text-xs font-medium capitalize transition-colors ${
                  typeFilter === t ? 'bg-primary text-white' : 'glass-light text-muted-foreground hover:text-foreground'
                }`}
              >
                {t}
              </button>
            ))}
          </div>
        )}

        {/* Category breakdown (expenses only) */}
        {records.filter((r) => r.type === 'expense').length > 0 && typeFilter !== 'income' && (
          <CategoryBreakdown records={records.filter((r) => r.type === 'expense')} />
        )}

        {/* Records list */}
        {filtered.length === 0 ? (
          <EmptyState hasRecords={records.length > 0} />
        ) : (
          <div className="flex flex-col gap-2">
            {filtered.map((record) => (
              <RecordCard
                key={record.id}
                record={record}
                onDelete={handleDelete}
                deleting={deletingId === record.id}
              />
            ))}
          </div>
        )}
      </div>
    </>
  )
}

function RecordCard({
  record,
  onDelete,
  deleting,
}: {
  record: FinancialRecord
  onDelete: (r: FinancialRecord) => void
  deleting: boolean
}) {
  const isExpense = record.type === 'expense'
  const color = CATEGORY_COLORS[record.category]
  const date = new Date(record.date)

  return (
    <Card variant="default" padding="md">
      <div className="flex items-start gap-3">
        <div
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl"
          style={{ background: `${color}18`, border: `1px solid ${color}30` }}
        >
          {isExpense
            ? <TrendingDown className="h-5 w-5" style={{ color }} />
            : <TrendingUp className="h-5 w-5 text-[hsl(152,62%,48%)]" />
          }
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <p className="text-sm font-medium text-foreground truncate">{record.title}</p>
              {record.description && (
                <p className="text-xs text-muted-foreground mt-0.5 line-clamp-1">{record.description}</p>
              )}
            </div>
            <div className="flex shrink-0 items-center gap-2">
              <span className={`text-sm font-bold ${isExpense ? 'text-destructive' : 'text-[hsl(152,62%,48%)]'}`}>
                {isExpense ? '-' : '+'}€{record.amount.toLocaleString()}
              </span>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => onDelete(record)}
                loading={deleting}
                aria-label="Delete record"
                className="h-7 w-7 shrink-0"
              >
                <Trash2 className="h-3.5 w-3.5 text-destructive" />
              </Button>
            </div>
          </div>
          <div className="mt-1.5 flex items-center gap-1.5">
            <Badge
              variant="neutral"
              size="xs"
              className="capitalize"
              style={{ color, borderColor: `${color}44`, background: `${color}18` }}
            >
              {record.category}
            </Badge>
            <span className="text-[10px] text-muted-foreground">
              {date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
            </span>
          </div>
        </div>
      </div>
    </Card>
  )
}

function CategoryBreakdown({ records }: { records: FinancialRecord[] }) {
  const totals: Partial<Record<FinanceCategory, number>> = {}
  for (const cat of EXPENSE_CATEGORIES) {
    const sum = records.filter((r) => r.category === cat).reduce((s, r) => s + r.amount, 0)
    if (sum > 0) totals[cat] = sum
  }

  const activeCats = (Object.keys(totals) as FinanceCategory[]).sort(
    (a, b) => (totals[b] ?? 0) - (totals[a] ?? 0)
  )
  if (activeCats.length === 0) return null

  const maxAmount = Math.max(...activeCats.map((c) => totals[c] ?? 0))

  return (
    <Card variant="default" padding="md">
      <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
        Expense Breakdown
      </p>
      <div className="flex flex-col gap-3">
        {activeCats.map((cat) => {
          const amount = totals[cat] ?? 0
          const pct = maxAmount > 0 ? (amount / maxAmount) * 100 : 0
          const color = CATEGORY_COLORS[cat]
          return (
            <div key={cat}>
              <div className="flex items-center justify-between mb-1">
                <span className="text-xs capitalize text-muted-foreground">{cat}</span>
                <span className="text-xs font-medium tabular-nums text-foreground">
                  €{amount.toLocaleString()}
                </span>
              </div>
              <div className="h-1.5 rounded-full bg-[rgba(255,255,255,0.06)] overflow-hidden">
                <div
                  className="h-full rounded-full transition-all duration-slow"
                  style={{ width: `${pct}%`, background: color }}
                />
              </div>
            </div>
          )
        })}
      </div>
    </Card>
  )
}

function EmptyState({ hasRecords }: { hasRecords: boolean }) {
  return (
    <div className="flex flex-col items-center gap-3 py-16 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-2xl glass-standard">
        <DollarSign className="h-7 w-7 text-muted-foreground" />
      </div>
      <p className="font-semibold text-foreground">
        {hasRecords ? 'No records match' : 'No financial records yet'}
      </p>
      <p className="text-sm text-muted-foreground max-w-[200px]">
        {hasRecords ? 'Try a different filter' : 'Log expenses, income, and budgets to track property costs'}
      </p>
    </div>
  )
}
