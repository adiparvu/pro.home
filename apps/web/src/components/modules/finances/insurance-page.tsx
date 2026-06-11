'use client'

import * as React from 'react'
import { Plus, Pencil, Trash2, ShieldCheck, X, AlertCircle, ExternalLink } from 'lucide-react'
import type { Property } from '@/lib/supabase/types'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'

export interface InsurancePolicy {
  id: string
  property_id: string
  provider: string
  policy_number: string | null
  policy_type: 'building' | 'contents' | 'landlord' | 'liability' | 'life' | 'other'
  premium_amount: number
  premium_frequency: 'monthly' | 'quarterly' | 'annual'
  start_date: string | null
  end_date: string | null
  coverage_amount: number | null
  currency: string
  notes: string | null
  document_url: string | null
  created_by: string | null
  created_at: string
}

interface InsurancePageProps {
  property: Property
  userId: string
  initialPolicies: InsurancePolicy[]
}

type PolicyType = InsurancePolicy['policy_type']

const POLICY_TYPE_OPTIONS: PolicyType[] = ['building', 'contents', 'landlord', 'liability', 'life', 'other']
const FREQUENCY_OPTIONS: InsurancePolicy['premium_frequency'][] = ['monthly', 'quarterly', 'annual']

const POLICY_TYPE_COLORS: Record<PolicyType, string> = {
  building:  'hsl(220,62%,52%)',
  contents:  'hsl(152,62%,42%)',
  landlord:  'hsl(270,62%,52%)',
  liability: 'hsl(22,68%,45%)',
  life:      'hsl(0,68%,44%)',
  other:     'hsl(0,0%,50%)',
}

function normalizeToAnnual(amount: number, freq: InsurancePolicy['premium_frequency']): number {
  if (freq === 'monthly') return amount * 12
  if (freq === 'quarterly') return amount * 4
  return amount
}

function daysUntil(dateStr: string | null): number | null {
  if (!dateStr) return null
  const diff = new Date(dateStr).getTime() - Date.now()
  return Math.ceil(diff / 86400_000)
}

function blankForm() {
  return {
    provider: '',
    policy_number: '',
    policy_type: 'building' as PolicyType,
    premium_amount: '',
    premium_frequency: 'annual' as InsurancePolicy['premium_frequency'],
    start_date: '',
    end_date: '',
    coverage_amount: '',
    currency: 'EUR',
    notes: '',
    document_url: '',
  }
}

export function InsurancePage({ property, userId, initialPolicies }: InsurancePageProps) {
  const confirmDialog = useConfirm()
  const [policies, setPolicies] = React.useState<InsurancePolicy[]>(initialPolicies)
  const [showModal, setShowModal] = React.useState(false)
  const [editingPolicy, setEditingPolicy] = React.useState<InsurancePolicy | null>(null)
  const [submitting, setSubmitting] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [formError, setFormError] = React.useState<string | null>(null)

  const [provider, setProvider] = React.useState('')
  const [policyNumber, setPolicyNumber] = React.useState('')
  const [policyType, setPolicyType] = React.useState<PolicyType>('building')
  const [premiumAmount, setPremiumAmount] = React.useState('')
  const [premiumFrequency, setPremiumFrequency] = React.useState<InsurancePolicy['premium_frequency']>('annual')
  const [startDate, setStartDate] = React.useState('')
  const [endDate, setEndDate] = React.useState('')
  const [coverageAmount, setCoverageAmount] = React.useState('')
  const [currency, setCurrency] = React.useState('EUR')
  const [notes, setNotes] = React.useState('')
  const [documentUrl, setDocumentUrl] = React.useState('')

  const totalAnnualPremium = policies.reduce((s, p) => s + normalizeToAnnual(p.premium_amount, p.premium_frequency), 0)

  function openAdd() {
    setEditingPolicy(null)
    const f = blankForm()
    setProvider(f.provider)
    setPolicyNumber(f.policy_number)
    setPolicyType(f.policy_type)
    setPremiumAmount(f.premium_amount)
    setPremiumFrequency(f.premium_frequency)
    setStartDate(f.start_date)
    setEndDate(f.end_date)
    setCoverageAmount(f.coverage_amount)
    setCurrency(f.currency)
    setNotes(f.notes)
    setDocumentUrl(f.document_url)
    setFormError(null)
    setShowModal(true)
  }

  function openEdit(p: InsurancePolicy) {
    setEditingPolicy(p)
    setProvider(p.provider)
    setPolicyNumber(p.policy_number ?? '')
    setPolicyType(p.policy_type)
    setPremiumAmount(String(p.premium_amount))
    setPremiumFrequency(p.premium_frequency)
    setStartDate(p.start_date ?? '')
    setEndDate(p.end_date ?? '')
    setCoverageAmount(p.coverage_amount != null ? String(p.coverage_amount) : '')
    setCurrency(p.currency)
    setNotes(p.notes ?? '')
    setDocumentUrl(p.document_url ?? '')
    setFormError(null)
    setShowModal(true)
  }

  function closeModal() {
    setShowModal(false)
    setEditingPolicy(null)
    setFormError(null)
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!provider.trim() || !premiumAmount) return
    setSubmitting(true)
    setFormError(null)

    const supabase = createClient()
    const payload = {
      provider: provider.trim(),
      policy_number: policyNumber.trim() || null,
      policy_type: policyType,
      premium_amount: parseFloat(premiumAmount),
      premium_frequency: premiumFrequency,
      start_date: startDate || null,
      end_date: endDate || null,
      coverage_amount: coverageAmount ? parseFloat(coverageAmount) : null,
      currency,
      notes: notes.trim() || null,
      document_url: documentUrl.trim() || null,
    }

    if (editingPolicy) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: updated, error } = await (supabase as any)
        .from('insurance_policies')
        .update(payload)
        .eq('id', editingPolicy.id)
        .select()
        .single()

      if (error) {
        setFormError((error as { message: string }).message ?? 'Failed to update policy')
        setSubmitting(false)
        return
      }
      setPolicies((prev) => prev.map((p) => (p.id === editingPolicy.id ? (updated as InsurancePolicy) : p)))
    } else {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: inserted, error } = await (supabase as any)
        .from('insurance_policies')
        .insert({ ...payload, property_id: property.id, created_by: userId })
        .select()
        .single()

      if (error) {
        setFormError((error as { message: string }).message ?? 'Failed to add policy')
        setSubmitting(false)
        return
      }
      setPolicies((prev) => [...prev, inserted as InsurancePolicy])
    }

    setSubmitting(false)
    closeModal()
  }

  async function handleDelete(p: InsurancePolicy) {
    const ok = await confirmDialog({
      title: `Delete ${p.provider} policy?`,
      description: `This will permanently remove the ${p.policy_type} insurance policy from ${p.provider}.`,
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(p.id)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error } = await (supabase as any).from('insurance_policies').delete().eq('id', p.id)
    if (error) {
      toast({ title: 'Error', description: 'Failed to delete policy', variant: 'destructive' })
    } else {
      setPolicies((prev) => prev.filter((x) => x.id !== p.id))
    }
    setDeletingId(null)
  }

  return (
    <>
      <PageHeader
        title="Insurance"
        description={property.name}
        action={{ label: 'Add policy', href: '#', onClick: openAdd }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6">

        {/* Summary card */}
        <Card variant="default" padding="sm">
          <div className="flex items-center gap-2 mb-1">
            <ShieldCheck className="h-4 w-4 text-[hsl(152,62%,52%)]" />
            <p className="text-xs text-muted-foreground">Total annual premium</p>
          </div>
          <p className="text-xl font-bold text-[hsl(152,62%,52%)]">
            €{Math.round(totalAnnualPremium).toLocaleString()}
            <span className="text-sm font-normal text-muted-foreground ml-1">/year</span>
          </p>
        </Card>

        {policies.length === 0 ? (
          <EmptyState onAdd={openAdd} />
        ) : (
          <div className="flex flex-col gap-3">
            {policies.map((p) => {
              const color = POLICY_TYPE_COLORS[p.policy_type]
              const days = daysUntil(p.end_date)
              const isExpiringSoon = days !== null && days >= 0 && days < 90
              const isExpiredOrUrgent = days !== null && days >= 0 && days < 30
              const annualPremium = normalizeToAnnual(p.premium_amount, p.premium_frequency)

              return (
                <Card key={p.id} variant="default" padding="md">
                  <div className="flex items-start gap-3">
                    <div
                      className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl"
                      style={{ background: `${color}18`, border: `1px solid ${color}30` }}
                    >
                      <ShieldCheck className="h-4.5 w-4.5" style={{ color }} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between gap-2 mb-0.5">
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className="text-sm font-semibold text-foreground">{p.provider}</span>
                          <Badge
                            variant="neutral"
                            size="xs"
                            className="text-[10px] capitalize"
                            style={{ color, borderColor: `${color}44`, background: `${color}18` }}
                          >
                            {p.policy_type}
                          </Badge>
                        </div>
                        <div className="flex items-center gap-1">
                          {p.document_url && (
                            <a
                              href={p.document_url}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground hover:text-foreground transition-colors"
                              aria-label="Open document"
                            >
                              <ExternalLink className="h-3.5 w-3.5" />
                            </a>
                          )}
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 shrink-0"
                            aria-label="Edit policy"
                            onClick={() => openEdit(p)}
                          >
                            <Pencil className="h-3.5 w-3.5 text-muted-foreground" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 shrink-0"
                            aria-label="Delete policy"
                            loading={deletingId === p.id}
                            onClick={() => { void handleDelete(p) }}
                          >
                            <Trash2 className="h-3.5 w-3.5 text-destructive" />
                          </Button>
                        </div>
                      </div>

                      {p.policy_number && (
                        <p className="text-[10px] text-muted-foreground mb-1.5">
                          Policy #{p.policy_number}
                        </p>
                      )}

                      <div className="grid grid-cols-2 gap-2 mb-2">
                        <div>
                          <p className="text-[10px] text-muted-foreground uppercase tracking-wider">Premium</p>
                          <p className="text-sm font-semibold tabular-nums">
                            {p.currency} {p.premium_amount.toLocaleString()}
                            <span className="text-xs font-normal text-muted-foreground"> / {p.premium_frequency}</span>
                          </p>
                          {p.premium_frequency !== 'annual' && (
                            <p className="text-[10px] text-muted-foreground">
                              ≈ {p.currency} {Math.round(annualPremium).toLocaleString()} /yr
                            </p>
                          )}
                        </div>
                        {p.coverage_amount != null && (
                          <div>
                            <p className="text-[10px] text-muted-foreground uppercase tracking-wider">Coverage</p>
                            <p className="text-sm font-semibold tabular-nums">{p.currency} {p.coverage_amount.toLocaleString()}</p>
                          </div>
                        )}
                      </div>

                      {p.end_date && (
                        <div className={cn(
                          'flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-xs font-medium',
                          isExpiredOrUrgent
                            ? 'bg-destructive/10 text-destructive'
                            : isExpiringSoon
                              ? 'bg-[hsl(45,75%,42%)]/10 text-[hsl(45,75%,42%)]'
                              : 'bg-muted/40 text-muted-foreground'
                        )}>
                          <AlertCircle className="h-3.5 w-3.5 shrink-0" />
                          Expires {new Date(p.end_date).toLocaleDateString('en', { year: 'numeric', month: 'short', day: 'numeric' })}
                          {days !== null && days >= 0 && (
                            <span className="ml-1 opacity-80">({days}d)</span>
                          )}
                          {days !== null && days < 0 && (
                            <span className="ml-1">(expired)</span>
                          )}
                        </div>
                      )}

                      {p.notes && (
                        <p className="mt-2 text-xs text-muted-foreground line-clamp-2">{p.notes}</p>
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
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm px-4"
          onClick={(e) => { if (e.target === e.currentTarget) closeModal() }}
        >
          <Card variant="default" padding="md" className="w-full max-w-sm max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between mb-4">
              <p className="text-sm font-semibold text-foreground">
                {editingPolicy ? 'Edit policy' : 'Add policy'}
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
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Provider *</label>
                <input
                  value={provider}
                  onChange={(e) => setProvider(e.target.value)}
                  placeholder="e.g. AXA, Aviva"
                  required
                  className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                />
              </div>

              <div className="flex flex-col gap-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Policy number</label>
                <input
                  value={policyNumber}
                  onChange={(e) => setPolicyNumber(e.target.value)}
                  placeholder="POL-123456"
                  className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                />
              </div>

              <div className="flex flex-col gap-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Policy type</label>
                <select
                  value={policyType}
                  onChange={(e) => setPolicyType(e.target.value as PolicyType)}
                  className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 capitalize"
                >
                  {POLICY_TYPE_OPTIONS.map((t) => (
                    <option key={t} value={t} className="capitalize">{t}</option>
                  ))}
                </select>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="flex flex-col gap-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Premium *</label>
                  <input
                    type="number"
                    value={premiumAmount}
                    onChange={(e) => setPremiumAmount(e.target.value)}
                    placeholder="450"
                    min="0"
                    step="0.01"
                    required
                    inputMode="decimal"
                    className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  />
                </div>
                <div className="flex flex-col gap-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Frequency</label>
                  <select
                    value={premiumFrequency}
                    onChange={(e) => setPremiumFrequency(e.target.value as InsurancePolicy['premium_frequency'])}
                    className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  >
                    {FREQUENCY_OPTIONS.map((f) => (
                      <option key={f} value={f} className="capitalize">{f}</option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="flex flex-col gap-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Coverage amount</label>
                <input
                  type="number"
                  value={coverageAmount}
                  onChange={(e) => setCoverageAmount(e.target.value)}
                  placeholder="500000"
                  min="0"
                  step="0.01"
                  inputMode="decimal"
                  className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="flex flex-col gap-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Start date</label>
                  <input
                    type="date"
                    value={startDate}
                    onChange={(e) => setStartDate(e.target.value)}
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
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Document URL</label>
                <input
                  type="url"
                  value={documentUrl}
                  onChange={(e) => setDocumentUrl(e.target.value)}
                  placeholder="https://..."
                  className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
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
                disabled={!provider.trim() || !premiumAmount}
              >
                {editingPolicy ? 'Update policy' : 'Add policy'}
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
        <ShieldCheck className="h-7 w-7 text-muted-foreground" />
      </div>
      <p className="font-semibold text-foreground">No insurance policies</p>
      <p className="text-sm text-muted-foreground max-w-[200px]">
        Keep all your property insurance policies in one place and track renewal dates
      </p>
      <Button variant="secondary" size="sm" onClick={onAdd}>
        <Plus className="h-3.5 w-3.5" />
        Add your first policy
      </Button>
    </div>
  )
}
