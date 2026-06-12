'use client'

import * as React from 'react'
import {
  Package, Truck, PackageCheck, PackageX, Plus, X, Loader2, Trash2, ExternalLink,
} from 'lucide-react'
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

type PackageStatus = 'expected' | 'out_for_delivery' | 'delivered' | 'missed' | 'returned'

interface Pkg {
  id: string
  property_id: string
  description: string
  carrier: string | null
  tracking_number: string | null
  expected_date: string | null
  received_at: string | null
  received_by: string | null
  status: PackageStatus
  notes: string | null
  added_by: string | null
  created_at: string
}

interface PackagesPageProps {
  property: Property
  userId: string
  initialPackages: Pkg[]
}

const STATUS_CONFIG: Record<PackageStatus, { label: string; color: string; icon: React.ComponentType<{ className?: string }> }> = {
  expected:         { label: 'Expected',         color: 'hsl(220,62%,52%)', icon: Package      },
  out_for_delivery: { label: 'Out for Delivery',  color: 'hsl(45,75%,42%)',  icon: Truck        },
  delivered:        { label: 'Delivered',          color: 'hsl(152,62%,38%)', icon: PackageCheck },
  missed:           { label: 'Missed',             color: 'hsl(0,68%,44%)',   icon: PackageX     },
  returned:         { label: 'Returned',           color: 'hsl(220,15%,50%)', icon: Package      },
}

const CARRIERS = ['DHL', 'UPS', 'FedEx', 'PostNL', 'DPD', 'GLS', 'Other']

const CARRIER_TRACKING: Record<string, string> = {
  DHL:    'https://www.dhl.com/en/express/tracking.html?AWB=',
  UPS:    'https://www.ups.com/track?tracknum=',
  FedEx:  'https://www.fedex.com/en-us/tracking.html?tracknumbers=',
  PostNL: 'https://jouw.postnl.nl/track-and-trace/',
  DPD:    'https://www.dpd.com/de/en/receiving-a-parcel/tracking/?parcelNo=',
  GLS:    'https://gls-group.com/track/',
}

function trackingUrl(carrier: string | null, tracking: string | null): string | null {
  if (!carrier || !tracking) return null
  const base = CARRIER_TRACKING[carrier]
  if (!base) return null
  return `${base}${tracking}`
}

function formatDate(d: string | null) {
  if (!d) return '—'
  return new Date(d + 'T00:00:00').toLocaleDateString('en', { day: 'numeric', month: 'short', year: 'numeric' })
}

type FilterMode = 'all' | 'pending' | 'delivered' | 'missed'

const EMPTY_FORM = {
  description: '',
  carrier: 'DHL',
  tracking_number: '',
  expected_date: '',
  notes: '',
}

export function PackagesPage({ property, userId, initialPackages }: PackagesPageProps) {
  const confirmDialog = useConfirm()
  const [packages, setPackages] = React.useState<Pkg[]>(initialPackages)
  const [filter, setFilter] = React.useState<FilterMode>('all')
  const [showForm, setShowForm] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [markingId, setMarkingId] = React.useState<string | null>(null)

  const [form, setForm] = React.useState(EMPTY_FORM)

  function setField<K extends keyof typeof EMPTY_FORM>(k: K, v: typeof EMPTY_FORM[K]) {
    setForm((prev) => ({ ...prev, [k]: v }))
  }

  const filtered = packages.filter((p) => {
    if (filter === 'pending') return p.status === 'expected' || p.status === 'out_for_delivery'
    if (filter === 'delivered') return p.status === 'delivered'
    if (filter === 'missed') return p.status === 'missed'
    return true
  })

  const counts = React.useMemo(() => ({
    all: packages.length,
    pending: packages.filter((p) => p.status === 'expected' || p.status === 'out_for_delivery').length,
    delivered: packages.filter((p) => p.status === 'delivered').length,
    missed: packages.filter((p) => p.status === 'missed').length,
  }), [packages])

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    if (!form.description.trim()) return
    setSaving(true)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('packages')
        .insert({
          property_id: property.id,
          description: form.description.trim(),
          carrier: form.carrier || null,
          tracking_number: form.tracking_number.trim() || null,
          expected_date: form.expected_date || null,
          notes: form.notes.trim() || null,
          status: 'expected',
          added_by: userId,
        })
        .select()
        .single()
      if (error) throw error
      setPackages((prev) => [data, ...prev])
      setForm(EMPTY_FORM)
      setShowForm(false)
      toast({ title: 'Package added' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  async function handleMarkDelivered(pkg: Pkg) {
    setMarkingId(pkg.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('packages')
        .update({ status: 'delivered', received_at: new Date().toISOString(), received_by: userId })
        .eq('id', pkg.id)
        .select()
        .single()
      if (error) throw error
      setPackages((prev) => prev.map((p) => (p.id === pkg.id ? data : p)))
      toast({ title: 'Marked as delivered' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setMarkingId(null)
    }
  }

  async function handleDelete(pkg: Pkg) {
    const ok = await confirmDialog({
      title: 'Delete package',
      description: `Delete "${pkg.description}"?`,
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(pkg.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('packages').delete().eq('id', pkg.id)
      setPackages((prev) => prev.filter((p) => p.id !== pkg.id))
      toast({ title: 'Package deleted' })
    } finally {
      setDeletingId(null)
    }
  }

  return (
    <>
      <PageHeader
        title="Packages"
        description={property.name}
        backHref="/household"
        action={{ label: 'Add Package', href: '#', onClick: () => setShowForm(true) }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Filter tabs */}
        <div className="flex gap-2 flex-wrap">
          {(['all', 'pending', 'delivered', 'missed'] as FilterMode[]).map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={cn(
                'px-3 py-1 rounded-full text-xs font-medium border transition-colors',
                filter === f
                  ? 'bg-primary text-white border-primary'
                  : 'border-border/50 text-muted-foreground hover:text-foreground'
              )}
            >
              {f.charAt(0).toUpperCase() + f.slice(1)}
              <span className="ml-1 opacity-60">({counts[f]})</span>
            </button>
          ))}
        </div>

        {filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
            <Package className="h-10 w-10 opacity-30" />
            <p className="text-sm">No packages yet</p>
            <Button size="sm" onClick={() => setShowForm(true)}>
              <Plus className="h-4 w-4 mr-1" />Add Package
            </Button>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {filtered.map((pkg) => {
              const cfg = STATUS_CONFIG[pkg.status]
              const StatusIcon = cfg.icon
              const trackUrl = trackingUrl(pkg.carrier, pkg.tracking_number)
              const isPending = pkg.status === 'expected' || pkg.status === 'out_for_delivery'

              return (
                <Card key={pkg.id} className="p-4">
                  <div className="flex items-start gap-3">
                    <div
                      className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg mt-0.5"
                      style={{ background: cfg.color + '20', color: cfg.color }}
                    >
                      <StatusIcon className="h-4 w-4" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-start justify-between gap-2">
                        <p className="font-medium text-sm">{pkg.description}</p>
                        <div className="flex items-center gap-1 shrink-0">
                          {isPending && (
                            <Button
                              variant="ghost"
                              size="sm"
                              className="h-7 px-2 text-xs"
                              onClick={() => handleMarkDelivered(pkg)}
                              disabled={markingId === pkg.id}
                            >
                              {markingId === pkg.id
                                ? <Loader2 className="h-3 w-3 animate-spin" />
                                : <PackageCheck className="h-3 w-3 mr-1" />}
                              Delivered
                            </Button>
                          )}
                          <button
                            onClick={() => handleDelete(pkg)}
                            disabled={deletingId === pkg.id}
                            className="p-1.5 text-muted-foreground hover:text-destructive transition-colors"
                          >
                            {deletingId === pkg.id
                              ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                              : <Trash2 className="h-3.5 w-3.5" />}
                          </button>
                        </div>
                      </div>

                      <div className="flex items-center gap-2 flex-wrap mt-1">
                        <Badge variant="neutral" style={{ borderColor: cfg.color + '60', color: cfg.color }}>
                          {cfg.label}
                        </Badge>
                        {pkg.carrier && (
                          <Badge variant="neutral" className="text-[10px]">{pkg.carrier}</Badge>
                        )}
                      </div>

                      <div className="mt-1.5 space-y-0.5 text-xs text-muted-foreground">
                        {pkg.tracking_number && (
                          <div className="flex items-center gap-1">
                            <span>Tracking: </span>
                            {trackUrl ? (
                              <a
                                href={trackUrl}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="text-primary hover:underline flex items-center gap-0.5"
                              >
                                {pkg.tracking_number}
                                <ExternalLink className="h-2.5 w-2.5" />
                              </a>
                            ) : (
                              <span>{pkg.tracking_number}</span>
                            )}
                          </div>
                        )}
                        {pkg.expected_date && (
                          <p>Expected: {formatDate(pkg.expected_date)}</p>
                        )}
                        {pkg.received_at && (
                          <p>Received: {new Date(pkg.received_at).toLocaleDateString('en', { day: 'numeric', month: 'short', year: 'numeric' })}</p>
                        )}
                        {pkg.notes && <p>{pkg.notes}</p>}
                      </div>
                    </div>
                  </div>
                </Card>
              )
            })}
          </div>
        )}
      </div>

      {/* Add package modal */}
      {showForm && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-md p-5 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">Add Package</h2>
              <button onClick={() => setShowForm(false)}>
                <X className="h-4 w-4 text-muted-foreground" />
              </button>
            </div>
            <form onSubmit={handleSave} className="space-y-3">
              <Input
                placeholder="Description *"
                value={form.description}
                onChange={(e) => setField('description', e.target.value)}
                required
              />
              <div className="grid grid-cols-2 gap-3">
                <select
                  value={form.carrier}
                  onChange={(e) => setField('carrier', e.target.value)}
                  className="rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                >
                  {CARRIERS.map((c) => (
                    <option key={c} value={c}>{c}</option>
                  ))}
                </select>
                <Input
                  placeholder="Tracking number"
                  value={form.tracking_number}
                  onChange={(e) => setField('tracking_number', e.target.value)}
                />
              </div>
              <div>
                <label className="text-xs text-muted-foreground">Expected date</label>
                <Input
                  type="date"
                  value={form.expected_date}
                  onChange={(e) => setField('expected_date', e.target.value)}
                />
              </div>
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
                  Add package
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}
