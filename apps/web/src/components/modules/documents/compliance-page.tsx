'use client'

import * as React from 'react'
import {
  ShieldCheck, Plus, X, Loader2, Trash2, Pencil,
  Zap, Flame, Droplets, AlertTriangle, FileCheck, ExternalLink,
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

interface ComplianceCert {
  id: string
  property_id: string
  cert_type: string
  issued_date: string | null
  expiry_date: string | null
  issued_by: string | null
  document_url: string | null
  notes: string | null
  created_by: string | null
  created_at: string
}

interface CompliancePageProps {
  property: Property
  userId: string
  initialCerts: ComplianceCert[]
}

type CertTypeKey = 'epc' | 'gas_safety' | 'electrical' | 'legionella' | 'fire' | 'asbestos' | 'other'

const CERT_TYPES: Record<CertTypeKey, { label: string; Icon: React.ComponentType<{ className?: string }> }> = {
  epc:        { label: 'Energy Performance Certificate', Icon: Zap },
  gas_safety: { label: 'Gas Safety Certificate',         Icon: Flame },
  electrical: { label: 'Electrical Safety (EICR)',       Icon: Zap },
  legionella: { label: 'Legionella Risk Assessment',     Icon: Droplets },
  fire:       { label: 'Fire Safety Certificate',        Icon: Flame },
  asbestos:   { label: 'Asbestos Survey',                Icon: AlertTriangle },
  other:      { label: 'Other Certificate',              Icon: FileCheck },
}

function daysUntilExpiry(expiryDate: string | null): number | null {
  if (!expiryDate) return null
  const diff = new Date(expiryDate + 'T00:00:00').getTime() - Date.now()
  return Math.ceil(diff / (1000 * 60 * 60 * 24))
}

function expiryColor(days: number | null): string {
  if (days === null) return 'hsl(152,62%,38%)'  // no expiry → green
  if (days < 0) return 'hsl(0,68%,44%)'          // expired → red
  if (days < 30) return 'hsl(0,68%,44%)'          // <30d → red
  if (days < 90) return 'hsl(45,75%,42%)'          // <90d → amber
  return 'hsl(152,62%,38%)'                          // >90d → green
}

function expiryLabel(days: number | null): string {
  if (days === null) return 'No expiry'
  if (days < 0) return `Expired ${Math.abs(days)}d ago`
  if (days === 0) return 'Expires today'
  return `${days}d left`
}

function formatDate(d: string | null) {
  if (!d) return '—'
  return new Date(d + 'T00:00:00').toLocaleDateString('en', { day: 'numeric', month: 'short', year: 'numeric' })
}

const EMPTY_FORM = {
  cert_type: 'other' as CertTypeKey,
  issued_date: '',
  expiry_date: '',
  issued_by: '',
  document_url: '',
  notes: '',
}

export function CompliancePage({ property, userId, initialCerts }: CompliancePageProps) {
  const confirmDialog = useConfirm()
  const [certs, setCerts] = React.useState<ComplianceCert[]>(initialCerts)
  const [showModal, setShowModal] = React.useState(false)
  const [editId, setEditId] = React.useState<string | null>(null)
  const [saving, setSaving] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [form, setForm] = React.useState(EMPTY_FORM)

  const selectCls = 'w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30'

  // Summary counts
  const validCount = certs.filter((c) => {
    const days = daysUntilExpiry(c.expiry_date)
    return days === null || days >= 90
  }).length
  const expiringSoonCount = certs.filter((c) => {
    const days = daysUntilExpiry(c.expiry_date)
    return days !== null && days >= 0 && days < 90
  }).length
  const expiredCount = certs.filter((c) => {
    const days = daysUntilExpiry(c.expiry_date)
    return days !== null && days < 0
  }).length

  function openNew() {
    setEditId(null)
    setForm(EMPTY_FORM)
    setShowModal(true)
  }

  function openEdit(c: ComplianceCert) {
    setEditId(c.id)
    setForm({
      cert_type: (c.cert_type as CertTypeKey) ?? 'other',
      issued_date: c.issued_date ?? '',
      expiry_date: c.expiry_date ?? '',
      issued_by: c.issued_by ?? '',
      document_url: c.document_url ?? '',
      notes: c.notes ?? '',
    })
    setShowModal(true)
  }

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    if (!form.cert_type) return
    setSaving(true)
    try {
      const supabase = createClient()
      const payload = {
        property_id: property.id,
        cert_type: form.cert_type,
        issued_date: form.issued_date || null,
        expiry_date: form.expiry_date || null,
        issued_by: form.issued_by.trim() || null,
        document_url: form.document_url.trim() || null,
        notes: form.notes.trim() || null,
        created_by: userId,
      }
      if (editId) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data, error } = await (supabase as any)
          .from('compliance_certificates').update(payload).eq('id', editId).select().single()
        if (error) throw error
        setCerts((prev) => prev.map((x) => (x.id === editId ? data as ComplianceCert : x)))
        toast({ title: 'Certificate updated' })
      } else {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data, error } = await (supabase as any)
          .from('compliance_certificates').insert(payload).select().single()
        if (error) throw error
        setCerts((prev) => [...prev, data as ComplianceCert].sort((a, b) => {
          if (!a.expiry_date) return 1
          if (!b.expiry_date) return -1
          return a.expiry_date.localeCompare(b.expiry_date)
        }))
        toast({ title: 'Certificate added' })
      }
      setShowModal(false)
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete(c: ComplianceCert) {
    const ok = await confirmDialog({
      title: 'Delete certificate',
      description: `Delete "${CERT_TYPES[c.cert_type as CertTypeKey]?.label ?? c.cert_type}"? This cannot be undone.`,
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(c.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('compliance_certificates').delete().eq('id', c.id)
      setCerts((prev) => prev.filter((x) => x.id !== c.id))
      toast({ title: 'Certificate deleted' })
    } finally {
      setDeletingId(null)
    }
  }

  return (
    <>
      <PageHeader
        title="Compliance"
        description={property.name}
        backHref="/documents"
        action={{ label: 'Add Certificate', href: '#', onClick: openNew }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Summary row */}
        {certs.length > 0 && (
          <div className="flex gap-3 flex-wrap">
            <div className="flex items-center gap-1.5 rounded-xl border border-border/30 px-3 py-1.5 text-xs">
              <span className="h-2 w-2 rounded-full bg-green-600" />
              <span className="font-medium text-muted-foreground">{validCount} valid</span>
            </div>
            <div className="flex items-center gap-1.5 rounded-xl border border-border/30 px-3 py-1.5 text-xs">
              <span className="h-2 w-2 rounded-full bg-amber-500" />
              <span className="font-medium text-muted-foreground">{expiringSoonCount} expiring soon</span>
            </div>
            <div className="flex items-center gap-1.5 rounded-xl border border-border/30 px-3 py-1.5 text-xs">
              <span className="h-2 w-2 rounded-full bg-red-600" />
              <span className="font-medium text-muted-foreground">{expiredCount} expired</span>
            </div>
          </div>
        )}

        {certs.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
            <ShieldCheck className="h-10 w-10 opacity-30" />
            <p className="text-sm">No compliance certificates yet</p>
            <Button size="sm" onClick={openNew}><Plus className="h-4 w-4 mr-1" />Add Certificate</Button>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {certs.map((c) => {
              const typeCfg = CERT_TYPES[c.cert_type as CertTypeKey] ?? CERT_TYPES.other
              const TypeIcon = typeCfg.Icon
              const days = daysUntilExpiry(c.expiry_date)
              const color = expiryColor(days)
              const isExpiring = days !== null && days >= 0 && days < 90
              const isExpired = days !== null && days < 0

              return (
                <Card key={c.id} className="p-4">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-start gap-3 flex-1">
                      <div
                        className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg mt-0.5"
                        style={{ background: color + '20', color }}
                      >
                        <TypeIcon className="h-4 w-4" />
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2 flex-wrap">
                          <p className="font-semibold text-sm">{typeCfg.label}</p>
                          <Badge variant="neutral" style={{ borderColor: color + '60', color }}>
                            {expiryLabel(days)}
                          </Badge>
                          {isExpired && (
                            <Badge variant="neutral" style={{ borderColor: 'hsl(0,68%,44%)60', color: 'hsl(0,68%,44%)' }}>
                              Renewal due
                            </Badge>
                          )}
                          {isExpiring && !isExpired && (
                            <Badge variant="neutral" style={{ borderColor: 'hsl(45,75%,42%)60', color: 'hsl(45,75%,42%)' }}>
                              Renewal due
                            </Badge>
                          )}
                        </div>
                        <div className="flex flex-wrap gap-x-3 gap-y-0.5 mt-1 text-xs text-muted-foreground">
                          {c.issued_by && <span>Issued by: {c.issued_by}</span>}
                          {c.issued_date && <span>Issued: {formatDate(c.issued_date)}</span>}
                          {c.expiry_date && <span>Expires: {formatDate(c.expiry_date)}</span>}
                        </div>
                        {c.notes && <p className="text-xs text-muted-foreground mt-1">{c.notes}</p>}
                        {c.document_url && (
                          <a
                            href={c.document_url}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="inline-flex items-center gap-1 text-xs text-primary hover:underline mt-1"
                          >
                            View document <ExternalLink className="h-3 w-3" />
                          </a>
                        )}
                      </div>
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      <button
                        onClick={() => openEdit(c)}
                        className="p-1.5 rounded-lg hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
                      >
                        <Pencil className="h-3.5 w-3.5" />
                      </button>
                      <button
                        onClick={() => handleDelete(c)}
                        disabled={deletingId === c.id}
                        className="p-1.5 rounded-lg hover:bg-destructive/10 transition-colors text-muted-foreground hover:text-destructive"
                      >
                        {deletingId === c.id
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
              <h2 className="font-semibold">{editId ? 'Edit Certificate' : 'Add Certificate'}</h2>
              <button onClick={() => setShowModal(false)}>
                <X className="h-4 w-4 text-muted-foreground" />
              </button>
            </div>
            <form onSubmit={handleSave} className="space-y-3">
              <div>
                <label className="text-xs text-muted-foreground">Certificate type *</label>
                <select
                  value={form.cert_type}
                  onChange={(e) => setForm((f) => ({ ...f, cert_type: e.target.value as CertTypeKey }))}
                  className={selectCls}
                  required
                >
                  {(Object.entries(CERT_TYPES) as [CertTypeKey, { label: string }][]).map(([key, { label }]) => (
                    <option key={key} value={key}>{label}</option>
                  ))}
                </select>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs text-muted-foreground">Issued date</label>
                  <Input
                    type="date"
                    value={form.issued_date}
                    onChange={(e) => setForm((f) => ({ ...f, issued_date: e.target.value }))}
                  />
                </div>
                <div>
                  <label className="text-xs text-muted-foreground">Expiry date</label>
                  <Input
                    type="date"
                    value={form.expiry_date}
                    onChange={(e) => setForm((f) => ({ ...f, expiry_date: e.target.value }))}
                  />
                </div>
              </div>
              <Input
                placeholder="Issued by"
                value={form.issued_by}
                onChange={(e) => setForm((f) => ({ ...f, issued_by: e.target.value }))}
              />
              <Input
                placeholder="Document URL (optional)"
                value={form.document_url}
                onChange={(e) => setForm((f) => ({ ...f, document_url: e.target.value }))}
              />
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
                  {editId ? 'Save changes' : 'Add certificate'}
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}
