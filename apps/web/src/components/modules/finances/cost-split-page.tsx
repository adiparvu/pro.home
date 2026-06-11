'use client'

import * as React from 'react'
import {
  Users, ChevronDown, ChevronUp, Plus, Trash2, Loader2, X,
  CheckSquare, Square, Check,
} from 'lucide-react'
import type { Property } from '@/lib/supabase/types'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'

export interface CostSplit {
  id: string
  property_id: string
  financial_record_id: string | null
  title: string
  total_amount: number
  currency: string
  status: 'open' | 'settled'
  created_by: string | null
}

export interface CostSplitShare {
  id: string
  split_id: string
  user_id: string | null
  member_name: string
  amount: number
  paid: boolean
  paid_at: string | null
}

interface CostSplitPageProps {
  property: Property
  userId: string
  initialSplits: CostSplit[]
  initialShares: CostSplitShare[]
}

interface ShareDraft {
  member_name: string
  amount: string
}

function blankShare(): ShareDraft {
  return { member_name: '', amount: '' }
}

export function CostSplitPage({ property, userId, initialSplits, initialShares }: CostSplitPageProps) {
  const confirmDialog = useConfirm()
  const [splits, setSplits] = React.useState<CostSplit[]>(initialSplits)
  const [shares, setShares] = React.useState<CostSplitShare[]>(initialShares)
  const [expandedIds, setExpandedIds] = React.useState<Set<string>>(new Set())
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [togglingShareId, setTogglingShareId] = React.useState<string | null>(null)
  const [settlingId, setSettlingId] = React.useState<string | null>(null)
  const [showModal, setShowModal] = React.useState(false)

  // Modal form state
  const [modalTitle, setModalTitle] = React.useState('')
  const [modalAmount, setModalAmount] = React.useState('')
  const [modalCurrency, setModalCurrency] = React.useState('EUR')
  const [modalShares, setModalShares] = React.useState<ShareDraft[]>([blankShare(), blankShare()])
  const [submitting, setSubmitting] = React.useState(false)
  const [formError, setFormError] = React.useState<string | null>(null)

  function toggleExpand(id: string) {
    setExpandedIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  function openModal() {
    setModalTitle('')
    setModalAmount('')
    setModalCurrency('EUR')
    setModalShares([blankShare(), blankShare()])
    setFormError(null)
    setShowModal(true)
  }

  function closeModal() {
    setShowModal(false)
    setFormError(null)
  }

  function addShareRow() {
    setModalShares((prev) => [...prev, blankShare()])
  }

  function removeShareRow(index: number) {
    setModalShares((prev) => prev.filter((_, i) => i !== index))
  }

  function updateShareRow(index: number, field: keyof ShareDraft, value: string) {
    setModalShares((prev) =>
      prev.map((s, i) => (i === index ? { ...s, [field]: value } : s))
    )
  }

  const sharesTotal = modalShares.reduce((sum, s) => {
    const n = parseFloat(s.amount)
    return sum + (isNaN(n) ? 0 : n)
  }, 0)
  const totalAmountNum = parseFloat(modalAmount)
  const totalMismatch =
    !isNaN(totalAmountNum) && totalAmountNum > 0 && Math.abs(sharesTotal - totalAmountNum) > 0.01

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!modalTitle.trim() || !modalAmount) return
    const validShares = modalShares.filter((s) => s.member_name.trim() && s.amount)
    if (validShares.length === 0) {
      setFormError('Add at least one person with an amount.')
      return
    }
    setFormError(null)
    setSubmitting(true)

    const supabase = createClient()

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: split, error: splitError } = await (supabase as any)
      .from('cost_splits')
      .insert({
        property_id: property.id,
        title: modalTitle.trim(),
        total_amount: parseFloat(modalAmount),
        currency: modalCurrency.trim() || 'EUR',
        status: 'open',
        created_by: userId,
        financial_record_id: null,
      })
      .select()
      .single()

    if (splitError || !split) {
      setFormError((splitError as { message?: string })?.message ?? 'Failed to create split')
      setSubmitting(false)
      return
    }

    const sharePayloads = validShares.map((s) => ({
      split_id: (split as CostSplit).id,
      user_id: null,
      member_name: s.member_name.trim(),
      amount: parseFloat(s.amount),
      paid: false,
      paid_at: null,
    }))

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: newShares, error: sharesError } = await (supabase as any)
      .from('cost_split_shares')
      .insert(sharePayloads)
      .select()

    if (sharesError) {
      setFormError((sharesError as { message?: string })?.message ?? 'Failed to save shares')
      setSubmitting(false)
      return
    }

    setSplits((prev) => [split as CostSplit, ...prev])
    setShares((prev) => [...prev, ...((newShares as CostSplitShare[]) ?? [])])
    setExpandedIds((prev) => new Set([...prev, (split as CostSplit).id]))
    setSubmitting(false)
    closeModal()
  }

  async function handleDelete(split: CostSplit) {
    const ok = await confirmDialog({
      title: `Delete "${split.title}"?`,
      description: 'This will permanently delete the split and all its shares.',
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(split.id)
    const supabase = createClient()

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('cost_split_shares').delete().eq('split_id', split.id)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error } = await (supabase as any).from('cost_splits').delete().eq('id', split.id)

    if (error) {
      toast({ title: 'Delete failed', description: (error as { message?: string })?.message, variant: 'destructive' })
      setDeletingId(null)
      return
    }

    setSplits((prev) => prev.filter((s) => s.id !== split.id))
    setShares((prev) => prev.filter((s) => s.split_id !== split.id))
    setDeletingId(null)
  }

  async function handleTogglePaid(share: CostSplitShare) {
    setTogglingShareId(share.id)
    const supabase = createClient()
    const newPaid = !share.paid

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: updated, error } = await (supabase as any)
      .from('cost_split_shares')
      .update({ paid: newPaid, paid_at: newPaid ? new Date().toISOString() : null })
      .eq('id', share.id)
      .select()
      .single()

    if (error || !updated) {
      toast({ title: 'Failed to update', description: (error as { message?: string })?.message, variant: 'destructive' })
      setTogglingShareId(null)
      return
    }

    setShares((prev) =>
      prev.map((s) => (s.id === share.id ? (updated as CostSplitShare) : s))
    )
    setTogglingShareId(null)
  }

  async function handleMarkSettled(split: CostSplit) {
    setSettlingId(split.id)
    const supabase = createClient()

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: updated, error } = await (supabase as any)
      .from('cost_splits')
      .update({ status: 'settled' })
      .eq('id', split.id)
      .select()
      .single()

    if (error || !updated) {
      toast({ title: 'Failed to settle', description: (error as { message?: string })?.message, variant: 'destructive' })
      setSettlingId(null)
      return
    }

    setSplits((prev) =>
      prev.map((s) => (s.id === split.id ? (updated as CostSplit) : s))
    )
    setSettlingId(null)
  }

  return (
    <>
      <PageHeader
        title="Cost Split"
        description={property.name}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6">
        {/* New Split button */}
        <Button variant="secondary" size="sm" onClick={openModal} className="self-start">
          <Plus className="h-3.5 w-3.5" />
          New split
        </Button>

        {/* Splits list */}
        {splits.length === 0 ? (
          <EmptyState />
        ) : (
          <div className="flex flex-col gap-3">
            {splits.map((split) => {
              const splitShares = shares.filter((s) => s.split_id === split.id)
              const paidCount = splitShares.filter((s) => s.paid).length
              const isExpanded = expandedIds.has(split.id)
              const isDeleting = deletingId === split.id
              const isSettling = settlingId === split.id

              return (
                <Card key={split.id} variant="default" padding="md">
                  {/* Header row */}
                  <div className="flex items-start gap-3">
                    <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary/10 border border-primary/20">
                      <Users className="h-5 w-5 text-primary" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-start justify-between gap-2">
                        <div className="min-w-0">
                          <p className="text-sm font-medium text-foreground truncate">{split.title}</p>
                          <p className="text-xs text-muted-foreground mt-0.5">
                            {split.total_amount.toLocaleString()} {split.currency}
                          </p>
                        </div>
                        <div className="flex shrink-0 items-center gap-1">
                          <Badge
                            variant="neutral"
                            size="xs"
                            className={cn(
                              split.status === 'settled'
                                ? 'text-[hsl(152,62%,48%)] border-[hsl(152,62%,42%)]/40 bg-[hsl(152,62%,42%)]/15'
                                : 'text-[hsl(220,62%,60%)] border-[hsl(220,62%,52%)]/40 bg-[hsl(220,62%,52%)]/15'
                            )}
                          >
                            {split.status === 'settled' ? 'SETTLED' : 'OPEN'}
                          </Badge>
                          <button
                            type="button"
                            onClick={() => toggleExpand(split.id)}
                            className="flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground hover:text-foreground transition-colors"
                            aria-label={isExpanded ? 'Collapse' : 'Expand'}
                          >
                            {isExpanded
                              ? <ChevronUp className="h-4 w-4" />
                              : <ChevronDown className="h-4 w-4" />}
                          </button>
                          <Button
                            variant="ghost"
                            size="icon"
                            onClick={() => handleDelete(split)}
                            loading={isDeleting}
                            aria-label="Delete split"
                            className="h-7 w-7 shrink-0"
                          >
                            <Trash2 className="h-3.5 w-3.5 text-destructive" />
                          </Button>
                        </div>
                      </div>

                      {/* Progress: X/N paid */}
                      {splitShares.length > 0 && (
                        <p className="text-[11px] text-muted-foreground mt-1">
                          {paidCount}/{splitShares.length} paid
                        </p>
                      )}
                    </div>
                  </div>

                  {/* Expanded shares */}
                  {isExpanded && (
                    <div className="mt-4 flex flex-col gap-2 border-t border-border/40 pt-4">
                      {splitShares.length === 0 ? (
                        <p className="text-xs text-muted-foreground text-center py-2">No shares yet</p>
                      ) : (
                        splitShares.map((share) => {
                          const isToggling = togglingShareId === share.id
                          return (
                            <div
                              key={share.id}
                              className="flex items-center justify-between gap-3"
                            >
                              <div className="flex items-center gap-2 min-w-0">
                                <button
                                  type="button"
                                  onClick={() => !isToggling && handleTogglePaid(share)}
                                  disabled={isToggling}
                                  className="shrink-0 text-muted-foreground hover:text-foreground transition-colors disabled:opacity-50"
                                  aria-label={share.paid ? 'Mark unpaid' : 'Mark paid'}
                                >
                                  {isToggling ? (
                                    <Loader2 className="h-4 w-4 animate-spin" />
                                  ) : share.paid ? (
                                    <CheckSquare className="h-4 w-4 text-[hsl(152,62%,48%)]" />
                                  ) : (
                                    <Square className="h-4 w-4" />
                                  )}
                                </button>
                                <span className={cn(
                                  'text-sm truncate',
                                  share.paid ? 'line-through text-muted-foreground' : 'text-foreground'
                                )}>
                                  {share.member_name}
                                </span>
                              </div>
                              <span className={cn(
                                'text-sm font-medium tabular-nums shrink-0',
                                share.paid ? 'text-muted-foreground line-through' : 'text-foreground'
                              )}>
                                {share.amount.toLocaleString()} {split.currency}
                              </span>
                            </div>
                          )
                        })
                      )}

                      {/* Mark settled button */}
                      {split.status === 'open' && (
                        <div className="mt-2 flex justify-end">
                          <Button
                            variant="secondary"
                            size="sm"
                            onClick={() => handleMarkSettled(split)}
                            loading={isSettling}
                            className="gap-1.5"
                          >
                            <Check className="h-3.5 w-3.5" />
                            Mark settled
                          </Button>
                        </div>
                      )}
                    </div>
                  )}
                </Card>
              )
            })}
          </div>
        )}
      </div>

      {/* New split modal */}
      {showModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm p-4">
          <Card variant="default" padding="md" className="w-full max-w-md max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between mb-5">
              <p className="text-sm font-semibold text-foreground">New cost split</p>
              <button
                type="button"
                onClick={closeModal}
                className="flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground hover:text-foreground transition-colors"
                aria-label="Close"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <form onSubmit={handleSubmit} className="flex flex-col gap-4">
              {formError && (
                <div className="rounded-xl border border-destructive/30 bg-destructive/10 px-3 py-2">
                  <p className="text-xs text-destructive">{formError}</p>
                </div>
              )}

              <div className="flex flex-col gap-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  Title *
                </label>
                <input
                  value={modalTitle}
                  onChange={(e) => setModalTitle(e.target.value)}
                  placeholder='e.g. "Groceries", "Utility bill"'
                  required
                  className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="flex flex-col gap-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                    Total amount *
                  </label>
                  <input
                    type="number"
                    value={modalAmount}
                    onChange={(e) => setModalAmount(e.target.value)}
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
                    value={modalCurrency}
                    onChange={(e) => setModalCurrency(e.target.value.toUpperCase())}
                    placeholder="EUR"
                    maxLength={4}
                    className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  />
                </div>
              </div>

              {/* Shares section */}
              <div className="flex flex-col gap-2">
                <div className="flex items-center justify-between">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                    Shares
                  </label>
                  {modalAmount && (
                    <span className={cn(
                      'text-xs tabular-nums font-medium',
                      totalMismatch ? 'text-destructive' : 'text-[hsl(152,62%,48%)]'
                    )}>
                      {sharesTotal.toFixed(2)} / {isNaN(totalAmountNum) ? '—' : totalAmountNum.toFixed(2)} {modalCurrency || 'EUR'}
                    </span>
                  )}
                </div>

                <div className="flex flex-col gap-2">
                  {modalShares.map((share, index) => (
                    <div key={index} className="flex items-center gap-2">
                      <input
                        value={share.member_name}
                        onChange={(e) => updateShareRow(index, 'member_name', e.target.value)}
                        placeholder="Name"
                        className="h-9 flex-1 rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                      />
                      <input
                        type="number"
                        value={share.amount}
                        onChange={(e) => updateShareRow(index, 'amount', e.target.value)}
                        placeholder="0.00"
                        min="0.01"
                        step="0.01"
                        inputMode="decimal"
                        className="h-9 w-24 rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                      />
                      {modalShares.length > 1 && (
                        <button
                          type="button"
                          onClick={() => removeShareRow(index)}
                          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl text-muted-foreground hover:text-destructive transition-colors"
                          aria-label="Remove person"
                        >
                          <X className="h-4 w-4" />
                        </button>
                      )}
                    </div>
                  ))}
                </div>

                <button
                  type="button"
                  onClick={addShareRow}
                  className="flex items-center gap-1.5 self-start rounded-xl px-2 py-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
                >
                  <Plus className="h-3.5 w-3.5" />
                  Add person
                </button>
              </div>

              <div className="flex gap-2 pt-1">
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={closeModal}
                  className="flex-1"
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  size="sm"
                  loading={submitting}
                  disabled={!modalTitle.trim() || !modalAmount}
                  className="flex-1"
                >
                  Create split
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}

function EmptyState() {
  return (
    <div className="flex flex-col items-center gap-3 py-16 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-2xl glass-standard">
        <Users className="h-7 w-7 text-muted-foreground" />
      </div>
      <p className="font-semibold text-foreground">No cost splits yet</p>
      <p className="text-sm text-muted-foreground max-w-[200px]">
        Split shared expenses among household members and track who has paid
      </p>
    </div>
  )
}
