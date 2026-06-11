'use client'

import * as React from 'react'
import { PieChart, Plus, X, Loader2, Trash2, AlertTriangle, Edit2 } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import type { Property } from '@/lib/supabase/types'

export interface PropertyShare {
  id: string
  property_id: string
  owner_name: string
  owner_email: string | null
  share_percentage: number
  acquisition_date: string | null
  notes: string | null
  created_by: string | null
  created_at: string
}

interface SharesPageProps {
  property: Property
  userId: string
  initialShares: PropertyShare[]
}

interface FinancialSummary {
  totalIncome: number
  totalExpenses: number
}

function hslForIndex(index: number) {
  const hue = (index * 137.5) % 360
  return `hsl(${hue.toFixed(0)}, 62%, 50%)`
}

function formatDate(d: string | null) {
  if (!d) return null
  return new Date(d + 'T00:00:00').toLocaleDateString('en', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  })
}

function fmtMoney(v: number) {
  return `€${v.toLocaleString('en', { maximumFractionDigits: 0 })}`
}

interface ShareModalProps {
  share?: PropertyShare | null
  onClose: () => void
  onSave: (data: Partial<PropertyShare>) => Promise<void>
  saving: boolean
}

function ShareModal({ share, onClose, onSave, saving }: ShareModalProps) {
  const [ownerName, setOwnerName] = React.useState(share?.owner_name ?? '')
  const [ownerEmail, setOwnerEmail] = React.useState(share?.owner_email ?? '')
  const [sharePercentage, setSharePercentage] = React.useState(
    share?.share_percentage?.toString() ?? ''
  )
  const [acquisitionDate, setAcquisitionDate] = React.useState(share?.acquisition_date ?? '')
  const [notes, setNotes] = React.useState(share?.notes ?? '')

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const pct = parseFloat(sharePercentage)
    if (!ownerName.trim()) {
      toast({ title: 'Owner name is required', variant: 'destructive' })
      return
    }
    if (isNaN(pct) || pct < 0.01 || pct > 100) {
      toast({ title: 'Share percentage must be between 0.01 and 100', variant: 'destructive' })
      return
    }
    await onSave({
      owner_name: ownerName.trim(),
      owner_email: ownerEmail.trim() || null,
      share_percentage: pct,
      acquisition_date: acquisitionDate || null,
      notes: notes.trim() || null,
    })
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm p-4">
      <Card className="w-full max-w-md p-6 flex flex-col gap-4">
        <div className="flex items-center justify-between">
          <p className="text-base font-semibold">
            {share ? 'Edit Share' : 'Add Share'}
          </p>
          <Button variant="ghost" size="icon" onClick={onClose}>
            <X className="h-4 w-4" />
          </Button>
        </div>
        <form onSubmit={handleSubmit} className="flex flex-col gap-3">
          <div className="flex flex-col gap-1">
            <label className="text-xs text-muted-foreground">Owner Name *</label>
            <Input
              value={ownerName}
              onChange={(e) => setOwnerName(e.target.value)}
              placeholder="Full name"
              required
            />
          </div>
          <div className="flex flex-col gap-1">
            <label className="text-xs text-muted-foreground">Owner Email</label>
            <Input
              type="email"
              value={ownerEmail}
              onChange={(e) => setOwnerEmail(e.target.value)}
              placeholder="email@example.com"
            />
          </div>
          <div className="flex flex-col gap-1">
            <label className="text-xs text-muted-foreground">Share Percentage *</label>
            <Input
              type="number"
              value={sharePercentage}
              onChange={(e) => setSharePercentage(e.target.value)}
              placeholder="e.g. 50"
              min="0.01"
              max="100"
              step="0.01"
              required
            />
          </div>
          <div className="flex flex-col gap-1">
            <label className="text-xs text-muted-foreground">Acquisition Date</label>
            <Input
              type="date"
              value={acquisitionDate}
              onChange={(e) => setAcquisitionDate(e.target.value)}
            />
          </div>
          <div className="flex flex-col gap-1">
            <label className="text-xs text-muted-foreground">Notes</label>
            <Input
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="Optional notes..."
            />
          </div>
          <div className="flex gap-2 pt-2">
            <Button type="button" variant="outline" onClick={onClose} className="flex-1">
              Cancel
            </Button>
            <Button type="submit" disabled={saving} className="flex-1">
              {saving ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
              {share ? 'Save Changes' : 'Add Share'}
            </Button>
          </div>
        </form>
      </Card>
    </div>
  )
}

export function SharesPage({ property, userId, initialShares }: SharesPageProps) {
  const [shares, setShares] = React.useState<PropertyShare[]>(initialShares)
  const [modalOpen, setModalOpen] = React.useState(false)
  const [editingShare, setEditingShare] = React.useState<PropertyShare | null>(null)
  const [saving, setSaving] = React.useState(false)
  const [financials, setFinancials] = React.useState<FinancialSummary | null>(null)
  const confirm = useConfirm()

  const supabase = React.useMemo(() => createClient(), [])

  // Fetch financial summary for pro-rata section
  React.useEffect(() => {
    async function loadFinancials() {
      const now = new Date()
      const yearStart = `${now.getFullYear()}-01-01`
      const yearEnd = `${now.getFullYear()}-12-31`

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data } = await (supabase as any)
        .from('financial_records')
        .select('type, amount')
        .eq('property_id', property.id)
        .gte('date', yearStart)
        .lte('date', yearEnd)

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      if (data) {
        const totalIncome = (data as any[])
          .filter((r) => r.type === 'income')
          .reduce((s: number, r: any) => s + (r.amount ?? 0), 0)
        const totalExpenses = (data as any[])
          .filter((r) => r.type === 'expense')
          .reduce((s: number, r: any) => s + (r.amount ?? 0), 0)
        setFinancials({ totalIncome, totalExpenses })
      }
    }
    loadFinancials()
  }, [supabase, property.id])

  const totalAllocated = shares.reduce((s, sh) => s + sh.share_percentage, 0)
  const remaining = 100 - totalAllocated
  const isOver = totalAllocated > 100

  const handleSave = async (data: Partial<PropertyShare>) => {
    setSaving(true)
    try {
      if (editingShare) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { error } = await (supabase as any)
          .from('property_shares')
          .update(data)
          .eq('id', editingShare.id)
        if (error) throw error
        setShares((prev) =>
          prev.map((s) => (s.id === editingShare.id ? { ...s, ...data } : s))
        )
        toast({ title: 'Share updated' })
      } else {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data: created, error } = await (supabase as any)
          .from('property_shares')
          .insert({ ...data, property_id: property.id, created_by: userId })
          .select()
          .single()
        if (error) throw error
        setShares((prev) =>
          [...prev, created as PropertyShare].sort(
            (a, b) => b.share_percentage - a.share_percentage
          )
        )
        toast({ title: 'Share added' })
      }
      setModalOpen(false)
      setEditingShare(null)
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to save share'
      toast({ title: msg, variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  const handleDelete = async (share: PropertyShare) => {
    const ok = await confirm({
      title: 'Delete share?',
      description: `Remove ${share.owner_name}'s ${share.share_percentage}% share from the register?`,
      confirmLabel: 'Delete',
    })
    if (!ok) return
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error } = await (supabase as any)
      .from('property_shares')
      .delete()
      .eq('id', share.id)
    if (error) {
      toast({ title: error.message, variant: 'destructive' })
      return
    }
    setShares((prev) => prev.filter((s) => s.id !== share.id))
    toast({ title: 'Share deleted' })
  }

  const openAdd = () => {
    setEditingShare(null)
    setModalOpen(true)
  }

  const openEdit = (share: PropertyShare) => {
    setEditingShare(share)
    setModalOpen(true)
  }

  return (
    <>
      <PageHeader
        title="Share Register"
        description={property.name}
        action={{ label: 'Add Share', href: '#', onClick: openAdd }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">

        {/* Summary */}
        <Card className="p-4 flex flex-col gap-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <PieChart className="h-4 w-4 text-muted-foreground" />
              <p className="text-sm font-medium">Ownership Summary</p>
            </div>
            <div className="flex items-center gap-2">
              <Badge
                variant="neutral"
                style={{
                  background: isOver ? 'hsl(0,68%,44%)22' : 'hsl(152,62%,38%)22',
                  color: isOver ? 'hsl(0,68%,44%)' : 'hsl(152,62%,38%)',
                }}
              >
                {totalAllocated.toFixed(2)}% allocated
              </Badge>
              {remaining > 0 && !isOver && (
                <Badge variant="neutral" style={{ background: 'hsl(45,75%,42%)22', color: 'hsl(45,75%,42%)' }}>
                  {remaining.toFixed(2)}% unallocated
                </Badge>
              )}
            </div>
          </div>

          {isOver && (
            <div className="flex items-center gap-2 text-sm text-red-600 dark:text-red-400">
              <AlertTriangle className="h-4 w-4 shrink-0" />
              <span>Total exceeds 100% — please adjust shares</span>
            </div>
          )}

          {/* Stacked bar */}
          {shares.length > 0 && (
            <div className="flex flex-col gap-1.5">
              <div className="flex h-5 w-full overflow-hidden rounded-full bg-muted">
                {shares.map((share, i) => {
                  const widthPct = Math.min((share.share_percentage / 100) * 100, 100)
                  return (
                    <div
                      key={share.id}
                      className="h-full transition-all"
                      style={{
                        width: `${widthPct}%`,
                        background: hslForIndex(i),
                        minWidth: share.share_percentage > 0 ? '2px' : '0',
                      }}
                      title={`${share.owner_name}: ${share.share_percentage}%`}
                    />
                  )
                })}
              </div>
              <div className="flex flex-wrap gap-2">
                {shares.map((share, i) => (
                  <div key={share.id} className="flex items-center gap-1">
                    <div
                      className="h-2.5 w-2.5 rounded-full shrink-0"
                      style={{ background: hslForIndex(i) }}
                    />
                    <span className="text-xs text-muted-foreground">{share.owner_name}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </Card>

        {/* Shares list */}
        {shares.length === 0 ? (
          <Card className="flex flex-col items-center gap-3 p-8 text-center">
            <PieChart className="h-8 w-8 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">No shares registered yet</p>
            <Button onClick={openAdd} size="sm">
              <Plus className="h-4 w-4 mr-1" /> Add first share
            </Button>
          </Card>
        ) : (
          <div className="flex flex-col gap-2">
            {shares.map((share, i) => (
              <Card key={share.id} className="p-4 flex items-start gap-3">
                <div
                  className="mt-0.5 h-3 w-3 rounded-full shrink-0"
                  style={{ background: hslForIndex(i) }}
                />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <p className="text-sm font-semibold">{share.owner_name}</p>
                    <Badge
                      variant="neutral"
                      style={{
                        background: `${hslForIndex(i)}22`,
                        color: hslForIndex(i),
                      }}
                    >
                      {share.share_percentage}%
                    </Badge>
                  </div>
                  {share.owner_email && (
                    <p className="text-xs text-muted-foreground mt-0.5">{share.owner_email}</p>
                  )}
                  {share.acquisition_date && (
                    <p className="text-xs text-muted-foreground">
                      Acquired: {formatDate(share.acquisition_date)}
                    </p>
                  )}
                  {share.notes && (
                    <p className="text-xs text-muted-foreground mt-1 italic">{share.notes}</p>
                  )}
                </div>
                <div className="flex gap-1 shrink-0">
                  <Button variant="ghost" size="icon" onClick={() => openEdit(share)}>
                    <Edit2 className="h-3.5 w-3.5" />
                  </Button>
                  <Button variant="ghost" size="icon" onClick={() => handleDelete(share)}>
                    <Trash2 className="h-3.5 w-3.5 text-red-500" />
                  </Button>
                </div>
              </Card>
            ))}
          </div>
        )}

        {/* Pro-rata finances section */}
        {financials && shares.length > 0 && (financials.totalIncome > 0 || financials.totalExpenses > 0) && (
          <Card className="p-0 overflow-hidden">
            <div className="px-4 py-3 border-b border-border/30">
              <p className="text-sm font-medium">Pro-rata Finances ({new Date().getFullYear()})</p>
              <p className="text-xs text-muted-foreground">Based on each owner&apos;s share percentage</p>
            </div>
            <div className="divide-y divide-border/30">
              {shares.map((share, i) => {
                const pct = share.share_percentage / 100
                const income = financials.totalIncome * pct
                const expenses = financials.totalExpenses * pct
                return (
                  <div key={share.id} className="px-4 py-3 flex items-center gap-3">
                    <div
                      className="h-2.5 w-2.5 rounded-full shrink-0"
                      style={{ background: hslForIndex(i) }}
                    />
                    <div className="flex-1">
                      <p className="text-sm font-medium">{share.owner_name}</p>
                      <p className="text-xs text-muted-foreground">{share.share_percentage}% share</p>
                    </div>
                    <div className="text-right flex flex-col gap-0.5">
                      {financials.totalIncome > 0 && (
                        <p className="text-xs">
                          <span className="text-muted-foreground">Income: </span>
                          <span className="font-medium text-green-600 dark:text-green-400">
                            {fmtMoney(income)}
                          </span>
                        </p>
                      )}
                      {financials.totalExpenses > 0 && (
                        <p className="text-xs">
                          <span className="text-muted-foreground">Expenses: </span>
                          <span className="font-medium text-red-600 dark:text-red-400">
                            {fmtMoney(expenses)}
                          </span>
                        </p>
                      )}
                    </div>
                  </div>
                )
              })}
            </div>
          </Card>
        )}
      </div>

      {(modalOpen || editingShare) && (
        <ShareModal
          share={editingShare}
          onClose={() => {
            setModalOpen(false)
            setEditingShare(null)
          }}
          onSave={handleSave}
          saving={saving}
        />
      )}
    </>
  )
}
