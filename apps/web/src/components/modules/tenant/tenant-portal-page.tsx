'use client'

import * as React from 'react'
import {
  MessageSquare, Plus, X, Loader2, Trash2, Copy, Check,
  Link2, ToggleLeft, ToggleRight, ChevronDown, ChevronUp,
  Clock, CheckCircle2, XCircle, AlertCircle,
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

interface TenantPortal {
  id: string
  property_id: string
  token: string
  label: string
  lease_id: string | null
  active: boolean
  created_by: string | null
  created_at: string
}

interface TenantRequest {
  id: string
  property_id: string
  portal_id: string | null
  tenant_name: string
  tenant_email: string | null
  title: string
  description: string | null
  category: string | null
  priority: string | null
  status: 'pending' | 'in_progress' | 'resolved' | 'rejected'
  created_at: string
  resolved_at: string | null
}

interface TenantPortalPageProps {
  property: Property
  userId: string
  initialPortals: TenantPortal[]
  initialRequests: TenantRequest[]
}

const CATEGORY_COLORS: Record<string, string> = {
  maintenance: 'hsl(22,68%,41%)',
  noise: 'hsl(280,68%,47%)',
  billing: 'hsl(45,75%,42%)',
  access: 'hsl(210,75%,42%)',
  other: 'hsl(220,15%,50%)',
}

const PRIORITY_COLORS: Record<string, string> = {
  low: 'hsl(152,62%,38%)',
  medium: 'hsl(45,75%,42%)',
  high: 'hsl(22,68%,41%)',
  urgent: 'hsl(0,68%,44%)',
}

const STATUS_CONFIG: Record<TenantRequest['status'], { label: string; color: string; Icon: React.ComponentType<{ className?: string }> }> = {
  pending:     { label: 'Pending',     color: 'hsl(45,75%,42%)',  Icon: Clock },
  in_progress: { label: 'In Progress', color: 'hsl(210,75%,42%)', Icon: AlertCircle },
  resolved:    { label: 'Resolved',    color: 'hsl(152,62%,38%)', Icon: CheckCircle2 },
  rejected:    { label: 'Rejected',    color: 'hsl(0,68%,44%)',   Icon: XCircle },
}

type RequestFilter = 'all' | 'pending' | 'in_progress' | 'resolved'

function formatDate(d: string) {
  return new Date(d).toLocaleDateString('en', { day: 'numeric', month: 'short', year: 'numeric' })
}

export function TenantPortalPage({ property, userId, initialPortals, initialRequests }: TenantPortalPageProps) {
  const confirmDialog = useConfirm()
  const [activeTab, setActiveTab] = React.useState<'portals' | 'requests'>('portals')
  const [portals, setPortals] = React.useState<TenantPortal[]>(initialPortals)
  const [requests, setRequests] = React.useState<TenantRequest[]>(initialRequests)
  const [expandedRequestId, setExpandedRequestId] = React.useState<string | null>(null)
  const [requestFilter, setRequestFilter] = React.useState<RequestFilter>('all')
  const [copiedToken, setCopiedToken] = React.useState<string | null>(null)

  const [showCreateModal, setShowCreateModal] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [togglingId, setTogglingId] = React.useState<string | null>(null)
  const [updatingRequestId, setUpdatingRequestId] = React.useState<string | null>(null)

  const [formLabel, setFormLabel] = React.useState('')
  const [formLeaseId, setFormLeaseId] = React.useState('')

  function getPortalUrl(token: string) {
    return `${window.location.origin}/tenant-portal/${token}`
  }

  async function copyLink(token: string) {
    try {
      await navigator.clipboard.writeText(getPortalUrl(token))
      setCopiedToken(token)
      setTimeout(() => setCopiedToken(null), 2000)
      toast({ title: 'Link copied' })
    } catch {
      toast({ title: 'Failed to copy', variant: 'destructive' })
    }
  }

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault()
    if (!formLabel.trim()) return
    setSaving(true)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('tenant_portals')
        .insert({
          property_id: property.id,
          label: formLabel.trim(),
          lease_id: formLeaseId || null,
          active: true,
          created_by: userId,
        })
        .select()
        .single()
      if (error) throw error
      setPortals((prev) => [data as TenantPortal, ...prev])
      setShowCreateModal(false)
      setFormLabel('')
      setFormLeaseId('')
      toast({ title: 'Portal created' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  async function toggleActive(portal: TenantPortal) {
    setTogglingId(portal.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('tenant_portals')
        .update({ active: !portal.active })
        .eq('id', portal.id)
        .select()
        .single()
      if (error) throw error
      setPortals((prev) => prev.map((p) => (p.id === portal.id ? data as TenantPortal : p)))
      toast({ title: portal.active ? 'Portal deactivated' : 'Portal activated' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setTogglingId(null)
    }
  }

  async function handleDeletePortal(portal: TenantPortal) {
    const ok = await confirmDialog({
      title: 'Delete portal',
      description: `Delete portal "${portal.label}"? This cannot be undone.`,
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(portal.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('tenant_portals').delete().eq('id', portal.id)
      setPortals((prev) => prev.filter((p) => p.id !== portal.id))
      toast({ title: 'Portal deleted' })
    } finally {
      setDeletingId(null)
    }
  }

  async function updateRequestStatus(req: TenantRequest, status: TenantRequest['status']) {
    setUpdatingRequestId(req.id)
    try {
      const supabase = createClient()
      const patch: Record<string, unknown> = { status }
      if (status === 'resolved') patch.resolved_at = new Date().toISOString()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('tenant_requests')
        .update(patch)
        .eq('id', req.id)
        .select()
        .single()
      if (error) throw error
      setRequests((prev) => prev.map((r) => (r.id === req.id ? data as TenantRequest : r)))
      toast({ title: 'Status updated' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setUpdatingRequestId(null)
    }
  }

  const filteredRequests = requestFilter === 'all'
    ? requests
    : requests.filter((r) => r.status === requestFilter)

  const pendingCount = requests.filter(r => r.status === 'pending').length

  return (
    <>
      <PageHeader
        title="Tenant Portal"
        description={property.name}
        action={{ label: 'Create Portal', href: '#', onClick: () => setShowCreateModal(true) }}
      />

      {/* Tabs */}
      <div className="px-4 md:px-6 pt-2 flex gap-2 border-b border-border/30">
        {(['portals', 'requests'] as const).map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
              activeTab === tab
                ? 'border-primary text-foreground'
                : 'border-transparent text-muted-foreground hover:text-foreground'
            }`}
          >
            {tab === 'portals' ? 'Portal Links' : 'Requests'}
            {tab === 'requests' && pendingCount > 0 && (
              <span className="ml-1.5 inline-flex items-center justify-center h-4 min-w-[16px] rounded-full bg-primary text-primary-foreground text-[10px] px-1">
                {pendingCount}
              </span>
            )}
          </button>
        ))}
      </div>

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {activeTab === 'portals' && (
          <>
            {portals.length === 0 ? (
              <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
                <Link2 className="h-10 w-10 opacity-30" />
                <p className="text-sm">No portal links yet</p>
                <Button size="sm" onClick={() => setShowCreateModal(true)}>
                  <Plus className="h-4 w-4 mr-1" />Create Portal
                </Button>
              </div>
            ) : (
              <div className="flex flex-col gap-3">
                {portals.map((portal) => (
                  <Card key={portal.id} className="p-4">
                    <div className="flex items-start justify-between gap-2">
                      <div className="flex items-start gap-3 flex-1">
                        <div
                          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg mt-0.5"
                          style={{ background: 'hsl(210,75%,42%,0.1)', color: 'hsl(210,75%,42%)' }}
                        >
                          <MessageSquare className="h-4 w-4" />
                        </div>
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center gap-2 flex-wrap">
                            <p className="font-semibold text-sm">{portal.label}</p>
                            <Badge variant="neutral" style={{
                              borderColor: portal.active ? 'hsl(152,62%,38%,0.6)' : 'hsl(220,15%,50%,0.6)',
                              color: portal.active ? 'hsl(152,62%,38%)' : 'hsl(220,15%,50%)',
                            }}>
                              {portal.active ? 'Active' : 'Inactive'}
                            </Badge>
                          </div>
                          <p className="text-xs text-muted-foreground mt-0.5">Created {formatDate(portal.created_at)}</p>
                          <p className="text-xs text-muted-foreground mt-1 font-mono truncate max-w-[280px]">
                            /tenant-portal/{portal.token}
                          </p>
                        </div>
                      </div>
                      <div className="flex items-center gap-1 shrink-0">
                        <button
                          onClick={() => copyLink(portal.token)}
                          className="p-1.5 rounded-lg hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
                          title="Copy link"
                        >
                          {copiedToken === portal.token
                            ? <Check className="h-3.5 w-3.5 text-green-600" />
                            : <Copy className="h-3.5 w-3.5" />}
                        </button>
                        <button
                          onClick={() => toggleActive(portal)}
                          disabled={togglingId === portal.id}
                          className="p-1.5 rounded-lg hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
                          title={portal.active ? 'Deactivate' : 'Activate'}
                        >
                          {togglingId === portal.id
                            ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                            : portal.active
                              ? <ToggleRight className="h-3.5 w-3.5 text-green-600" />
                              : <ToggleLeft className="h-3.5 w-3.5" />}
                        </button>
                        <button
                          onClick={() => handleDeletePortal(portal)}
                          disabled={deletingId === portal.id}
                          className="p-1.5 rounded-lg hover:bg-destructive/10 transition-colors text-muted-foreground hover:text-destructive"
                        >
                          {deletingId === portal.id
                            ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                            : <Trash2 className="h-3.5 w-3.5" />}
                        </button>
                      </div>
                    </div>
                  </Card>
                ))}
              </div>
            )}
          </>
        )}

        {activeTab === 'requests' && (
          <>
            {/* Filter */}
            <div className="flex gap-2 flex-wrap">
              {(['all', 'pending', 'in_progress', 'resolved'] as const).map((f) => (
                <button
                  key={f}
                  onClick={() => setRequestFilter(f)}
                  className={`px-3 py-1 rounded-full text-xs font-medium transition-colors ${
                    requestFilter === f
                      ? 'bg-primary text-primary-foreground'
                      : 'bg-muted text-muted-foreground hover:text-foreground'
                  }`}
                >
                  {f === 'all' ? 'All' : f === 'in_progress' ? 'In Progress' : f.charAt(0).toUpperCase() + f.slice(1)}
                </button>
              ))}
            </div>

            {filteredRequests.length === 0 ? (
              <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
                <MessageSquare className="h-10 w-10 opacity-30" />
                <p className="text-sm">No requests</p>
              </div>
            ) : (
              <div className="flex flex-col gap-3">
                {filteredRequests.map((req) => {
                  const statusCfg = STATUS_CONFIG[req.status]
                  const StatusIcon = statusCfg.Icon
                  const isExpanded = expandedRequestId === req.id
                  return (
                    <Card key={req.id} className="p-4">
                      <button
                        className="flex items-start gap-3 w-full text-left"
                        onClick={() => setExpandedRequestId(isExpanded ? null : req.id)}
                      >
                        <div
                          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg mt-0.5"
                          style={{ background: statusCfg.color + '20', color: statusCfg.color }}
                        >
                          <StatusIcon className="h-4 w-4" />
                        </div>
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center gap-2 flex-wrap">
                            <p className="font-semibold text-sm">{req.title}</p>
                            <Badge variant="neutral" style={{ borderColor: statusCfg.color + '60', color: statusCfg.color }}>
                              {statusCfg.label}
                            </Badge>
                            {req.category && (
                              <Badge variant="neutral" style={{
                                borderColor: (CATEGORY_COLORS[req.category] ?? CATEGORY_COLORS['other']!) + '60',
                                color: CATEGORY_COLORS[req.category] ?? CATEGORY_COLORS['other'],
                              }}>
                                {req.category}
                              </Badge>
                            )}
                            {req.priority && (
                              <Badge variant="neutral" style={{
                                borderColor: (PRIORITY_COLORS[req.priority] ?? PRIORITY_COLORS['low']!) + '60',
                                color: PRIORITY_COLORS[req.priority] ?? PRIORITY_COLORS['low'],
                              }}>
                                {req.priority}
                              </Badge>
                            )}
                          </div>
                          <p className="text-xs text-muted-foreground mt-0.5">{req.tenant_name} · {formatDate(req.created_at)}</p>
                        </div>
                        <span className="text-muted-foreground mt-1">
                          {isExpanded ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                        </span>
                      </button>

                      {isExpanded && (
                        <div className="mt-3 pt-3 border-t border-border/30 space-y-2 text-sm">
                          {req.tenant_email && (
                            <p className="text-xs text-muted-foreground">
                              Email: <a href={`mailto:${req.tenant_email}`} className="hover:text-foreground">{req.tenant_email}</a>
                            </p>
                          )}
                          {req.description && (
                            <p className="text-sm text-muted-foreground">{req.description}</p>
                          )}
                          <div className="flex gap-2 flex-wrap pt-1">
                            {req.status === 'pending' && (
                              <Button
                                size="sm"
                                variant="ghost"
                                className="h-7 px-2 text-xs"
                                disabled={updatingRequestId === req.id}
                                onClick={() => updateRequestStatus(req, 'in_progress')}
                              >
                                {updatingRequestId === req.id && <Loader2 className="h-3 w-3 animate-spin mr-1" />}
                                Mark in progress
                              </Button>
                            )}
                            {(req.status === 'pending' || req.status === 'in_progress') && (
                              <Button
                                size="sm"
                                variant="ghost"
                                className="h-7 px-2 text-xs text-green-700 hover:text-green-700 hover:bg-green-50"
                                disabled={updatingRequestId === req.id}
                                onClick={() => updateRequestStatus(req, 'resolved')}
                              >
                                {updatingRequestId === req.id && <Loader2 className="h-3 w-3 animate-spin mr-1" />}
                                Mark resolved
                              </Button>
                            )}
                            {req.status !== 'rejected' && req.status !== 'resolved' && (
                              <Button
                                size="sm"
                                variant="ghost"
                                className="h-7 px-2 text-xs text-destructive hover:text-destructive hover:bg-destructive/10"
                                disabled={updatingRequestId === req.id}
                                onClick={() => updateRequestStatus(req, 'rejected')}
                              >
                                Reject
                              </Button>
                            )}
                          </div>
                        </div>
                      )}
                    </Card>
                  )
                })}
              </div>
            )}
          </>
        )}
      </div>

      {/* Create Portal Modal */}
      {showCreateModal && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-sm p-5 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">Create Portal Link</h2>
              <button onClick={() => setShowCreateModal(false)}>
                <X className="h-4 w-4 text-muted-foreground" />
              </button>
            </div>
            <form onSubmit={handleCreate} className="space-y-3">
              <Input
                placeholder="Label (e.g. Unit 3A) *"
                value={formLabel}
                onChange={(e) => setFormLabel(e.target.value)}
                required
              />
              <div>
                <label className="text-xs text-muted-foreground">Lease ID (optional)</label>
                <Input
                  placeholder="Lease ID"
                  value={formLeaseId}
                  onChange={(e) => setFormLeaseId(e.target.value)}
                />
              </div>
              <div className="flex justify-end gap-2">
                <Button type="button" variant="ghost" size="sm" onClick={() => setShowCreateModal(false)}>Cancel</Button>
                <Button type="submit" size="sm" disabled={saving}>
                  {saving && <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />}
                  Create
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}
