'use client'

import * as React from 'react'
import {
  DollarSign, TrendingDown, TrendingUp, Plus, Trash2, Pencil, Paperclip,
  ChevronDown, ChevronUp, AlertCircle, Tag, X, Download,
} from 'lucide-react'
import type { Property, FinancialRecord, FinanceCategory, FinanceType } from '@/lib/supabase/types'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { SegmentedControl } from '@/components/ui/segmented-control'
import { toast } from '@/hooks/use-toast'

interface FinancesPageProps {
  property: Property
  userId: string
  initialRecords: FinancialRecord[]
  initialShowForm?: boolean
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

const TYPE_CONFIG: Record<FinanceType, { label: string; color: string; bg: string }> = {
  expense: { label: 'Expense', color: 'text-destructive',       bg: 'bg-destructive/20 border-destructive/30' },
  income:  { label: 'Income',  color: 'text-[hsl(152,62%,48%)]', bg: 'bg-[hsl(152,62%,42%)]/20 border-[hsl(152,62%,42%)]/30' },
  budget:  { label: 'Budget',  color: 'text-[hsl(220,62%,60%)]', bg: 'bg-[hsl(220,62%,52%)]/20 border-[hsl(220,62%,52%)]/30' },
}

function blankForm() {
  return {
    title: '',
    amount: '',
    type: 'expense' as FinanceType,
    category: 'other' as FinanceCategory,
    date: new Date().toISOString().split('T')[0] ?? '',
    description: '',
    tags: [] as string[],
    receiptFile: null as File | null,
  }
}

export function FinancesPage({ property, userId, initialRecords, initialShowForm = false }: FinancesPageProps) {
  const confirmDialog = useConfirm()
  const [records, setRecords] = React.useState<FinancialRecord[]>(initialRecords)
  const [typeFilter, setTypeFilter] = React.useState<FinanceType | 'all'>('all')
  const [showForm, setShowForm] = React.useState(initialShowForm)
  const [submitting, setSubmitting] = React.useState(false)
  const [formError, setFormError] = React.useState<string | null>(null)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [editingId, setEditingId] = React.useState<string | null>(null)

  // Form fields
  const [title, setTitle] = React.useState('')
  const [amount, setAmount] = React.useState('')
  const [type, setType] = React.useState<FinanceType>('expense')
  const [category, setCategory] = React.useState<FinanceCategory>('other')
  const [date, setDate] = React.useState(() => new Date().toISOString().split('T')[0] ?? '')
  const [description, setDescription] = React.useState('')
  const [tags, setTags] = React.useState<string[]>([])
  const [tagInput, setTagInput] = React.useState('')
  const [receiptFile, setReceiptFile] = React.useState<File | null>(null)

  const filtered = typeFilter === 'all' ? records : records.filter((r) => r.type === typeFilter)

  const totalExpenses = records.filter((r) => r.type === 'expense').reduce((s, r) => s + r.amount, 0)
  const totalIncome = records.filter((r) => r.type === 'income').reduce((s, r) => s + r.amount, 0)
  const balance = totalIncome - totalExpenses

  const currentYear = new Date().getFullYear()
  const ytdExpenses = records
    .filter((r) => r.type === 'expense' && new Date(r.date).getFullYear() === currentYear)
    .reduce((s, r) => s + r.amount, 0)

  function openAdd() {
    setEditingId(null)
    const f = blankForm()
    setTitle(f.title)
    setAmount(f.amount)
    setType(f.type)
    setCategory(f.category)
    setDate(f.date)
    setDescription(f.description)
    setTags(f.tags)
    setTagInput('')
    setReceiptFile(null)
    setFormError(null)
    setShowForm(true)
  }

  function startEdit(record: FinancialRecord) {
    setEditingId(record.id)
    setTitle(record.title)
    setAmount(String(record.amount))
    setType(record.type)
    setCategory(record.category)
    setDate(record.date)
    setDescription(record.description ?? '')
    setTags(record.tags ?? [])
    setTagInput('')
    setReceiptFile(null)
    setFormError(null)
    setShowForm(true)
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  function cancelForm() {
    setShowForm(false)
    setEditingId(null)
    setFormError(null)
  }

  function exportCSV() {
    const rows = [
      ['Date', 'Title', 'Type', 'Category', 'Amount (EUR)', 'Description', 'Tags', 'Receipt'],
      ...records.map((r) => [
        r.date,
        `"${r.title.replace(/"/g, '""')}"`,
        r.type,
        r.category,
        r.amount.toFixed(2),
        `"${(r.description ?? '').replace(/"/g, '""')}"`,
        `"${r.tags.join('; ')}"`,
        r.receipt_url ?? '',
      ]),
    ]
    const csv = rows.map((r) => r.join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `finances-${property.name.toLowerCase().replace(/\s+/g, '-')}-${new Date().toISOString().split('T')[0]}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  function addTag(raw: string) {
    const tag = raw.trim().toLowerCase()
    if (!tag || tags.includes(tag)) return
    setTags((prev) => [...prev, tag])
    setTagInput('')
  }

  async function uploadReceipt(file: File, recordId: string): Promise<string | null> {
    const supabase = createClient()
    const path = `${property.id}/${recordId}/${Date.now()}-${file.name}`
    const { error } = await supabase.storage.from('financial-receipts').upload(path, file)
    if (error) return null
    return supabase.storage.from('financial-receipts').getPublicUrl(path).data.publicUrl
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!title.trim() || !amount) return
    setSubmitting(true)
    setFormError(null)

    const supabase = createClient()
    const payload = {
      title: title.trim(),
      amount: parseFloat(amount),
      currency: 'EUR',
      type,
      category,
      date,
      description: description.trim() || null,
      tags,
    }

    if (editingId) {
      // Update existing record
      let receiptUrl: string | null | undefined = undefined
      if (receiptFile) {
        receiptUrl = await uploadReceipt(receiptFile, editingId)
      }
      const updatePayload = receiptUrl !== undefined ? { ...payload, receipt_url: receiptUrl } : payload
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: updated, error } = await (supabase as any)
        .from('financial_records')
        .update(updatePayload)
        .eq('id', editingId)
        .select()
        .single()

      if (error) {
        setFormError((error as { message: string }).message ?? 'Failed to update record')
        setSubmitting(false)
        return
      }
      setRecords((prev) =>
        prev
          .map((r) => (r.id === editingId ? (updated as FinancialRecord) : r))
          .sort((a, b) => b.date.localeCompare(a.date))
      )
    } else {
      // Insert new record
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: record, error } = await (supabase as any)
        .from('financial_records')
        .insert({ ...payload, property_id: property.id, created_by: userId })
        .select()
        .single()

      if (error) {
        setFormError((error as { message: string }).message ?? 'Failed to save record')
        setSubmitting(false)
        return
      }

      // Upload receipt after insert (need the record id)
      if (receiptFile && record) {
        const receiptUrl = await uploadReceipt(receiptFile, (record as FinancialRecord).id)
        if (receiptUrl) {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const { data: withReceipt } = await (supabase as any)
            .from('financial_records')
            .update({ receipt_url: receiptUrl })
            .eq('id', (record as FinancialRecord).id)
            .select()
            .single()
          setRecords((prev) =>
            [withReceipt as FinancialRecord, ...prev].sort((a, b) => b.date.localeCompare(a.date))
          )
          setSubmitting(false)
          cancelForm()
          return
        }
      }

      setRecords((prev) => [record as FinancialRecord, ...prev].sort((a, b) => b.date.localeCompare(a.date)))
    }

    setSubmitting(false)
    cancelForm()
  }

  async function handleDelete(record: FinancialRecord) {
    const ok = await confirmDialog({
      title: `Delete "${record.title}"?`,
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(record.id)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('financial_records').delete().eq('id', record.id)
    toast.success('Record deleted')
    setRecords((prev) => prev.filter((r) => r.id !== record.id))
    if (editingId === record.id) cancelForm()
    setDeletingId(null)
  }

  return (
    <>
      <PageHeader
        title="Finances"
        description={property.name}
        action={records.length > 0 ? { label: 'Export CSV', href: '#', onClick: exportCSV } : undefined}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6">
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

        {/* Monthly trend chart */}
        <MonthlyTrendChart records={records} />

        {/* Add record toggle */}
        {!showForm && (
          <Button variant="secondary" size="sm" onClick={openAdd} className="self-start">
            <Plus className="h-3.5 w-3.5" />
            Log expense / income
            <ChevronDown className="h-3.5 w-3.5" />
          </Button>
        )}

        {/* Add / Edit form */}
        {showForm && (
          <Card variant="default" padding="md">
            <div className="flex items-center justify-between mb-4">
              <p className="text-sm font-semibold text-foreground">
                {editingId ? 'Edit record' : 'New record'}
              </p>
              <button
                type="button"
                onClick={cancelForm}
                className="flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground hover:text-foreground transition-colors"
              >
                <ChevronUp className="h-4 w-4" />
              </button>
            </div>

            <form onSubmit={handleSubmit} className="flex flex-col gap-4">
              {formError && (
                <div className="flex items-center gap-2 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2">
                  <AlertCircle className="h-3.5 w-3.5 text-destructive shrink-0" />
                  <p className="text-xs text-destructive">{formError}</p>
                </div>
              )}

              {/* Type toggle */}
              <div className="flex gap-2">
                {(Object.keys(TYPE_CONFIG) as FinanceType[]).map((t) => {
                  const cfg = TYPE_CONFIG[t]
                  return (
                    <button
                      key={t}
                      type="button"
                      onClick={() => setType(t)}
                      className={`flex-1 rounded-xl py-2 text-xs font-medium transition-colors border ${
                        type === t ? `${cfg.bg} ${cfg.color}` : 'glass-light text-muted-foreground hover:text-foreground border-transparent'
                      }`}
                    >
                      {cfg.label}
                    </button>
                  )
                })}
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

              {/* Tags */}
              <div className="flex flex-col gap-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Tags</label>
                {tags.length > 0 && (
                  <div className="flex flex-wrap gap-1.5">
                    {tags.map((tag) => (
                      <span
                        key={tag}
                        className="flex items-center gap-1 rounded-full border border-border glass-light px-2.5 py-0.5 text-xs text-foreground"
                      >
                        {tag}
                        <button
                          type="button"
                          onClick={() => setTags((prev) => prev.filter((t) => t !== tag))}
                          className="text-muted-foreground hover:text-destructive"
                        >
                          <X className="h-3 w-3" />
                        </button>
                      </span>
                    ))}
                  </div>
                )}
                <input
                  value={tagInput}
                  onChange={(e) => setTagInput(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') { e.preventDefault(); addTag(tagInput) }
                  }}
                  placeholder="Type and press Enter"
                  className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                />
              </div>

              {/* Receipt upload */}
              <div className="flex flex-col gap-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Receipt</label>
                <label className="flex h-10 cursor-pointer items-center gap-2 rounded-xl border border-dashed border-border glass-light px-3 text-sm text-muted-foreground hover:text-foreground transition-colors">
                  <Paperclip className="h-4 w-4 shrink-0" />
                  <span className="truncate">
                    {receiptFile ? receiptFile.name : 'Attach receipt (image or PDF)'}
                  </span>
                  <input
                    type="file"
                    accept="image/*,.pdf"
                    className="sr-only"
                    onChange={(e) => setReceiptFile(e.target.files?.[0] ?? null)}
                  />
                </label>
              </div>

              <Button type="submit" size="sm" loading={submitting} disabled={!title.trim() || !amount}>
                {editingId ? 'Update record' : 'Save record'}
              </Button>
            </form>
          </Card>
        )}

        {/* Filter tabs */}
        {records.length > 0 && (
          <SegmentedControl
            aria-label="Record type"
            size="sm"
            value={typeFilter}
            onChange={setTypeFilter}
            options={[
              { value: 'all', label: 'All' },
              { value: 'expense', label: 'Expenses' },
              { value: 'income', label: 'Income' },
              { value: 'budget', label: 'Budget' },
            ]}
          />
        )}

        {/* Budget vs Actual (shown when budget records exist) */}
        {records.filter((r) => r.type === 'budget').length > 0 && typeFilter !== 'income' && (
          <BudgetVsActual
            budgetRecords={records.filter((r) => r.type === 'budget')}
            expenseRecords={records.filter((r) => r.type === 'expense')}
          />
        )}

        {/* Category breakdown (expenses only) */}
        {records.filter((r) => r.type === 'expense').length > 0 && typeFilter !== 'income' && typeFilter !== 'budget' && (
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
                onEdit={startEdit}
                deleting={deletingId === record.id}
                editing={editingId === record.id}
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
  onEdit,
  deleting,
  editing,
}: {
  record: FinancialRecord
  onDelete: (r: FinancialRecord) => void
  onEdit: (r: FinancialRecord) => void
  deleting: boolean
  editing: boolean
}) {
  const isExpense = record.type === 'expense'
  const isBudget = record.type === 'budget'
  const color = CATEGORY_COLORS[record.category]
  const date = new Date(record.date)
  const amountColor = isExpense
    ? 'text-destructive'
    : isBudget
      ? 'text-[hsl(220,62%,60%)]'
      : 'text-[hsl(152,62%,48%)]'
  const amountPrefix = isExpense ? '-' : isBudget ? '' : '+'

  return (
    <Card
      variant="default"
      padding="md"
      className={editing ? 'ring-2 ring-primary/40' : ''}
    >
      <div className="flex items-start gap-3">
        <div
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl"
          style={{ background: `${color}18`, border: `1px solid ${color}30` }}
        >
          {isExpense
            ? <TrendingDown className="h-5 w-5" style={{ color }} />
            : isBudget
              ? <DollarSign className="h-5 w-5" style={{ color }} />
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
            <div className="flex shrink-0 items-center gap-1">
              <span className={`text-sm font-bold ${amountColor}`}>
                {amountPrefix}€{record.amount.toLocaleString()}
              </span>
              <button
                type="button"
                onClick={() => onEdit(record)}
                className="flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground hover:text-foreground transition-colors"
                aria-label="Edit record"
              >
                <Pencil className="h-3.5 w-3.5" />
              </button>
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
          <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
            <Badge
              variant="neutral"
              size="xs"
              className="capitalize"
              style={{ color, borderColor: `${color}44`, background: `${color}18` }}
            >
              {record.category}
            </Badge>
            {record.type === 'budget' && (
              <Badge variant="neutral" size="xs" style={{ color: 'hsl(220,62%,60%)' }}>budget</Badge>
            )}
            <span className="text-[10px] text-muted-foreground">
              {date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
            </span>
            {record.tags.map((tag) => (
              <span key={tag} className="flex items-center gap-0.5 text-[10px] text-muted-foreground">
                <Tag className="h-2.5 w-2.5" />
                {tag}
              </span>
            ))}
            {record.receipt_url && (
              <a
                href={record.receipt_url}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-0.5 text-[10px] text-primary hover:underline"
              >
                <Paperclip className="h-2.5 w-2.5" />
                receipt
              </a>
            )}
          </div>
        </div>
      </div>
    </Card>
  )
}

function MonthlyTrendChart({ records }: { records: FinancialRecord[] }) {
  const now = new Date()
  const months = Array.from({ length: 6 }, (_, i) => {
    const d = new Date(now.getFullYear(), now.getMonth() - (5 - i), 1)
    return {
      key: `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`,
      label: d.toLocaleString('en-US', { month: 'short' }),
      expenses: 0,
      income: 0,
    }
  })

  for (const r of records) {
    const slot = months.find((m) => m.key === r.date.substring(0, 7))
    if (!slot) continue
    if (r.type === 'expense') slot.expenses += r.amount
    else if (r.type === 'income') slot.income += r.amount
  }

  if (!months.some((m) => m.expenses > 0 || m.income > 0)) return null

  const max = Math.max(...months.flatMap((m) => [m.expenses, m.income]), 1)
  const W = 300, H = 120
  const PAD = { top: 10, right: 8, bottom: 24, left: 38 }
  const chartW = W - PAD.left - PAD.right
  const chartH = H - PAD.top - PAD.bottom
  const slotW = chartW / 6
  const barW = slotW * 0.28

  const yTicks = [0, 1, 2, 3].map((i) => (max * i) / 3)

  function yPos(val: number) {
    return PAD.top + chartH - (val / max) * chartH
  }
  function fmt(n: number) {
    return n >= 1000 ? `${(n / 1000).toFixed(0)}k` : `${Math.round(n)}`
  }

  return (
    <Card variant="default" padding="md">
      <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
        Monthly Trend
      </p>
      <svg
        viewBox={`0 0 ${W} ${H}`}
        preserveAspectRatio="xMidYMid meet"
        className="w-full"
        style={{ height: 120 }}
      >
        {yTicks.map((val, i) => {
          const y = yPos(val)
          return (
            <g key={i}>
              <line x1={PAD.left} y1={y} x2={W - PAD.right} y2={y} stroke="currentColor" strokeOpacity={0.06} strokeWidth={1} />
              <text x={PAD.left - 4} y={y + 3} textAnchor="end" fontSize={7} fill="currentColor" opacity={0.4}>{fmt(val)}</text>
            </g>
          )
        })}
        {months.map((month, i) => {
          const cx = PAD.left + slotW * i + slotW / 2
          return (
            <g key={month.key}>
              {month.expenses > 0 && (
                <rect
                  x={cx - barW - 1} y={yPos(month.expenses)}
                  width={barW} height={(month.expenses / max) * chartH}
                  rx={2} fill="hsl(0,68%,52%)" opacity={0.75}
                />
              )}
              {month.income > 0 && (
                <rect
                  x={cx + 1} y={yPos(month.income)}
                  width={barW} height={(month.income / max) * chartH}
                  rx={2} fill="hsl(152,62%,48%)" opacity={0.75}
                />
              )}
              <text x={cx} y={H - 4} textAnchor="middle" fontSize={8} fill="currentColor" opacity={0.5}>
                {month.label}
              </text>
            </g>
          )
        })}
      </svg>
      <div className="flex items-center gap-4 mt-1">
        <div className="flex items-center gap-1.5">
          <div className="h-2 w-2 rounded-sm bg-destructive/75" />
          <span className="text-[10px] text-muted-foreground">Expenses</span>
        </div>
        <div className="flex items-center gap-1.5">
          <div className="h-2 w-2 rounded-sm" style={{ background: 'hsl(152,62%,48%,0.75)' }} />
          <span className="text-[10px] text-muted-foreground">Income</span>
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

function BudgetVsActual({
  budgetRecords,
  expenseRecords,
}: {
  budgetRecords: FinancialRecord[]
  expenseRecords: FinancialRecord[]
}) {
  // Sum budgets per category
  const budgets: Partial<Record<FinanceCategory, number>> = {}
  for (const r of budgetRecords) {
    budgets[r.category] = (budgets[r.category] ?? 0) + r.amount
  }

  // Sum YTD expenses per category
  const currentYear = new Date().getFullYear().toString()
  const actuals: Partial<Record<FinanceCategory, number>> = {}
  for (const r of expenseRecords.filter((r) => r.date.startsWith(currentYear))) {
    actuals[r.category] = (actuals[r.category] ?? 0) + r.amount
  }

  const cats = (Object.keys(budgets) as FinanceCategory[]).sort(
    (a, b) => (budgets[b] ?? 0) - (budgets[a] ?? 0)
  )
  if (cats.length === 0) return null

  const totalBudget = cats.reduce((s, c) => s + (budgets[c] ?? 0), 0)
  const totalActual = cats.reduce((s, c) => s + (actuals[c] ?? 0), 0)
  const totalPct = totalBudget > 0 ? Math.round((totalActual / totalBudget) * 100) : 0

  return (
    <Card variant="default" padding="md">
      <div className="flex items-center justify-between mb-3">
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
          Budget vs Actual
        </p>
        <span
          className={`text-xs font-bold tabular-nums ${
            totalPct > 100 ? 'text-destructive' : totalPct > 80 ? 'text-[hsl(45,75%,52%)]' : 'text-[hsl(152,62%,48%)]'
          }`}
        >
          {totalPct}% of €{totalBudget.toLocaleString()} used
        </span>
      </div>
      <div className="flex flex-col gap-3">
        {cats.map((cat) => {
          const budget = budgets[cat] ?? 0
          const actual = actuals[cat] ?? 0
          const pct = budget > 0 ? Math.min((actual / budget) * 100, 110) : 0
          const rawPct = budget > 0 ? (actual / budget) * 100 : 0
          const isOver = rawPct > 100
          const isWarn = rawPct > 80
          const barColor = isOver
            ? 'hsl(0,68%,52%)'
            : isWarn
              ? 'hsl(45,75%,52%)'
              : CATEGORY_COLORS[cat]
          const color = CATEGORY_COLORS[cat]

          return (
            <div key={cat}>
              <div className="flex items-center justify-between mb-1">
                <span className="text-xs capitalize text-muted-foreground">{cat}</span>
                <span className="flex items-center gap-1.5">
                  <span className={`text-xs font-medium tabular-nums ${isOver ? 'text-destructive' : 'text-foreground'}`}>
                    €{actual.toLocaleString()}
                  </span>
                  <span className="text-[10px] text-muted-foreground">/ €{budget.toLocaleString()}</span>
                  {isOver && (
                    <span className="text-[10px] font-bold text-destructive">
                      +{Math.round(rawPct - 100)}%
                    </span>
                  )}
                </span>
              </div>
              <div className="h-2 rounded-full overflow-hidden" style={{ background: `${color}14` }}>
                <div
                  className="h-full rounded-full transition-all duration-slow"
                  style={{ width: `${pct}%`, background: barColor }}
                />
              </div>
            </div>
          )
        })}
      </div>
      <p className="mt-3 text-[10px] text-muted-foreground">
        Comparing YTD {currentYear} expenses against logged budget records
      </p>
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
