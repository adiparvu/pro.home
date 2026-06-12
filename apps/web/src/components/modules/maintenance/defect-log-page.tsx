'use client'

import * as React from 'react'
import { Bug, Plus, Pencil, Trash2, X, Loader2, CheckCircle, ChevronDown, ChevronUp, ImageIcon } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import { PhotoGallery } from '@/components/ui/photo-gallery'
import type { Property } from '@/lib/supabase/types'

export interface DefectLog {
  id: string
  property_id: string
  room_id: string | null
  title: string
  description: string | null
  severity: 'critical' | 'major' | 'minor'
  status: 'open' | 'in_progress' | 'resolved'
  photo_urls: string[]
  reported_date: string
  resolved_date: string | null
  cost: number | null
  currency: string | null
  notes: string | null
  created_by: string | null
  created_at: string
}

export interface Room {
  id: string
  name: string
}

interface DefectLogPageProps {
  property: Property
  userId: string
  initialDefects: DefectLog[]
  rooms: Room[]
}

const SEVERITY_COLORS: Record<string, string> = {
  critical: 'hsl(0,68%,44%)',
  major: 'hsl(45,75%,42%)',
  minor: 'hsl(210,0%,50%)',
}

const STATUS_COLORS: Record<string, string> = {
  open: 'hsl(0,68%,44%)',
  in_progress: 'hsl(45,75%,42%)',
  resolved: 'hsl(152,62%,38%)',
}

const SEVERITIES = ['critical', 'major', 'minor'] as const
const STATUSES = ['open', 'in_progress', 'resolved'] as const

function fmtDate(d: string | null) {
  if (!d) return '—'
  return new Date(d).toLocaleDateString('en', { day: 'numeric', month: 'short', year: 'numeric' })
}

type StatusFilter = 'all' | 'open' | 'in_progress' | 'resolved'

export function DefectLogPage({ property, userId, initialDefects, rooms }: DefectLogPageProps) {
  const confirmDialog = useConfirm()
  const [defects, setDefects] = React.useState<DefectLog[]>(initialDefects)
  const [statusFilter, setStatusFilter] = React.useState<StatusFilter>('all')
  const [showForm, setShowForm] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [resolvingId, setResolvingId] = React.useState<string | null>(null)
  const [editId, setEditId] = React.useState<string | null>(null)
  const [expandedId, setExpandedId] = React.useState<string | null>(null)

  // Form state
  const [title, setTitle] = React.useState('')
  const [severity, setSeverity] = React.useState<'critical' | 'major' | 'minor'>('minor')
  const [status, setStatus] = React.useState<'open' | 'in_progress' | 'resolved'>('open')
  const [roomId, setRoomId] = React.useState<string>('')
  const [description, setDescription] = React.useState('')
  const [reportedDate, setReportedDate] = React.useState(() => new Date().toISOString().split('T')[0] ?? '')
  const [resolvedDate, setResolvedDate] = React.useState('')
  const [cost, setCost] = React.useState('')
  const [currency, setCurrency] = React.useState('EUR')
  const [notes, setNotes] = React.useState('')

  function openNew() {
    setEditId(null)
    setTitle('')
    setSeverity('minor')
    setStatus('open')
    setRoomId('')
    setDescription('')
    setReportedDate(new Date().toISOString().split('T')[0] ?? '')
    setResolvedDate('')
    setCost('')
    setCurrency('EUR')
    setNotes('')
    setShowForm(true)
  }

  function openEdit(d: DefectLog) {
    setEditId(d.id)
    setTitle(d.title)
    setSeverity(d.severity)
    setStatus(d.status)
    setRoomId(d.room_id ?? '')
    setDescription(d.description ?? '')
    setReportedDate(d.reported_date)
    setResolvedDate(d.resolved_date ?? '')
    setCost(d.cost != null ? String(d.cost) : '')
    setCurrency(d.currency ?? 'EUR')
    setNotes(d.notes ?? '')
    setShowForm(true)
  }

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    if (!title.trim()) return
    setSaving(true)
    try {
      const supabase = createClient()
      const payload = {
        property_id: property.id,
        title: title.trim(),
        severity,
        status,
        room_id: roomId || null,
        description: description.trim() || null,
        reported_date: reportedDate,
        resolved_date: resolvedDate || null,
        cost: cost ? parseFloat(cost) : null,
        currency: currency || null,
        notes: notes.trim() || null,
        photo_urls: [],
        created_by: userId,
      }
      if (editId) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data, error } = await (supabase as any)
          .from('defect_logs')
          .update({
            title: payload.title,
            severity,
            status,
            room_id: payload.room_id,
            description: payload.description,
            reported_date: payload.reported_date,
            resolved_date: payload.resolved_date,
            cost: payload.cost,
            currency: payload.currency,
            notes: payload.notes,
          })
          .eq('id', editId)
          .select()
          .single()
        if (error) throw error
        setDefects((prev) => prev.map((x) => (x.id === editId ? data as DefectLog : x)))
        toast({ title: 'Defect updated' })
      } else {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data, error } = await (supabase as any)
          .from('defect_logs')
          .insert(payload)
          .select()
          .single()
        if (error) throw error
        setDefects((prev) => [data as DefectLog, ...prev])
        toast({ title: 'Defect logged' })
      }
      setShowForm(false)
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete(d: DefectLog) {
    const ok = await confirmDialog({
      title: 'Delete defect',
      description: `Delete "${d.title}"? This cannot be undone.`,
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(d.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('defect_logs').delete().eq('id', d.id)
      setDefects((prev) => prev.filter((x) => x.id !== d.id))
      toast({ title: 'Defect deleted' })
    } finally {
      setDeletingId(null)
    }
  }

  async function handleMarkResolved(d: DefectLog) {
    setResolvingId(d.id)
    try {
      const supabase = createClient()
      const today = new Date().toISOString().split('T')[0]
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('defect_logs')
        .update({ status: 'resolved', resolved_date: today })
        .eq('id', d.id)
        .select()
        .single()
      if (error) throw error
      setDefects((prev) => prev.map((x) => (x.id === d.id ? data as DefectLog : x)))
      toast({ title: 'Marked as resolved' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setResolvingId(null)
    }
  }

  const filtered = statusFilter === 'all' ? defects : defects.filter((d) => d.status === statusFilter)

  const openCount = defects.filter((d) => d.status !== 'resolved')
  const criticalOpen = openCount.filter((d) => d.severity === 'critical').length
  const majorOpen = openCount.filter((d) => d.severity === 'major').length
  const minorOpen = openCount.filter((d) => d.severity === 'minor').length

  const grouped = {
    critical: filtered.filter((d) => d.severity === 'critical'),
    major: filtered.filter((d) => d.severity === 'major'),
    minor: filtered.filter((d) => d.severity === 'minor'),
  }

  const roomMap = React.useMemo(() => {
    const m: Record<string, string> = {}
    for (const r of rooms) m[r.id] = r.name
    return m
  }, [rooms])

  const FILTER_OPTIONS: { value: StatusFilter; label: string }[] = [
    { value: 'all', label: 'All' },
    { value: 'open', label: 'Open' },
    { value: 'in_progress', label: 'In Progress' },
    { value: 'resolved', label: 'Resolved' },
  ]

  return (
    <>
      <PageHeader
        title="Defect Log"
        description={property.name}
        backHref="/maintenance"
        action={{ label: 'Log Defect', href: '#', onClick: openNew }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Summary row */}
        {(criticalOpen > 0 || majorOpen > 0 || minorOpen > 0) && (
          <div className="flex flex-wrap gap-2">
            {criticalOpen > 0 && (
              <Badge variant="neutral" style={{ color: SEVERITY_COLORS.critical, borderColor: `${SEVERITY_COLORS.critical}44`, background: `${SEVERITY_COLORS.critical}18` }}>
                {criticalOpen} critical open
              </Badge>
            )}
            {majorOpen > 0 && (
              <Badge variant="neutral" style={{ color: SEVERITY_COLORS.major, borderColor: `${SEVERITY_COLORS.major}44`, background: `${SEVERITY_COLORS.major}18` }}>
                {majorOpen} major open
              </Badge>
            )}
            {minorOpen > 0 && (
              <Badge variant="neutral">
                {minorOpen} minor open
              </Badge>
            )}
          </div>
        )}

        {/* Filter chips */}
        <div className="flex gap-2 flex-wrap">
          {FILTER_OPTIONS.map((opt) => (
            <button
              key={opt.value}
              onClick={() => setStatusFilter(opt.value)}
              className={`rounded-full px-3 py-1 text-xs font-medium border transition-colors ${
                statusFilter === opt.value
                  ? 'bg-primary text-primary-foreground border-primary'
                  : 'border-border/50 text-muted-foreground hover:text-foreground'
              }`}
            >
              {opt.label}
            </button>
          ))}
        </div>

        {defects.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
            <Bug className="h-10 w-10 opacity-30" />
            <p className="text-sm">No defects logged yet</p>
            <Button size="sm" onClick={openNew}><Plus className="h-4 w-4 mr-1" />Log Defect</Button>
          </div>
        ) : (
          <>
            {(['critical', 'major', 'minor'] as const).map((sev) => {
              const items = grouped[sev]
              if (items.length === 0) return null
              return (
                <div key={sev} className="space-y-2">
                  <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground capitalize">
                    {sev} ({items.length})
                  </p>
                  {items.map((d) => (
                    <DefectCard
                      key={d.id}
                      defect={d}
                      roomName={d.room_id ? (roomMap[d.room_id] ?? null) : null}
                      expanded={expandedId === d.id}
                      onToggleExpand={() => setExpandedId(expandedId === d.id ? null : d.id)}
                      onEdit={() => openEdit(d)}
                      onDelete={() => handleDelete(d)}
                      onMarkResolved={() => handleMarkResolved(d)}
                      onPhotosChange={(photos) => setDefects((prev) => prev.map((x) => x.id === d.id ? { ...x, photo_urls: photos } : x))}
                      property={property}
                      deleting={deletingId === d.id}
                      resolving={resolvingId === d.id}
                    />
                  ))}
                </div>
              )
            })}
            {filtered.length === 0 && (
              <div className="flex flex-col items-center gap-2 py-10 text-muted-foreground">
                <p className="text-sm">No defects match this filter</p>
              </div>
            )}
          </>
        )}
      </div>

      {/* Form modal */}
      {showForm && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-lg p-5 space-y-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">{editId ? 'Edit Defect' : 'Log New Defect'}</h2>
              <button onClick={() => setShowForm(false)} className="text-muted-foreground hover:text-foreground">
                <X className="h-4 w-4" />
              </button>
            </div>
            <form onSubmit={handleSave} className="space-y-3">
              <Input
                placeholder="Title *"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                required
              />
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs text-muted-foreground mb-1 block">Severity *</label>
                  <select
                    value={severity}
                    onChange={(e) => setSeverity(e.target.value as typeof severity)}
                    className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                  >
                    {SEVERITIES.map((s) => (
                      <option key={s} value={s}>{s.charAt(0).toUpperCase() + s.slice(1)}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="text-xs text-muted-foreground mb-1 block">Status *</label>
                  <select
                    value={status}
                    onChange={(e) => setStatus(e.target.value as typeof status)}
                    className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                  >
                    {STATUSES.map((s) => (
                      <option key={s} value={s}>{s.replace('_', ' ').replace(/\b\w/g, (c) => c.toUpperCase())}</option>
                    ))}
                  </select>
                </div>
              </div>
              {rooms.length > 0 && (
                <div>
                  <label className="text-xs text-muted-foreground mb-1 block">Room (optional)</label>
                  <select
                    value={roomId}
                    onChange={(e) => setRoomId(e.target.value)}
                    className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                  >
                    <option value="">— None —</option>
                    {rooms.map((r) => (
                      <option key={r.id} value={r.id}>{r.name}</option>
                    ))}
                  </select>
                </div>
              )}
              <textarea
                placeholder="Description (optional)"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                rows={2}
                className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs text-muted-foreground mb-1 block">Reported Date</label>
                  <Input
                    type="date"
                    value={reportedDate}
                    onChange={(e) => setReportedDate(e.target.value)}
                  />
                </div>
                <div>
                  <label className="text-xs text-muted-foreground mb-1 block">Resolved Date</label>
                  <Input
                    type="date"
                    value={resolvedDate}
                    onChange={(e) => setResolvedDate(e.target.value)}
                  />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs text-muted-foreground mb-1 block">Cost (optional)</label>
                  <Input
                    type="number"
                    min="0"
                    step="0.01"
                    placeholder="0.00"
                    value={cost}
                    onChange={(e) => setCost(e.target.value)}
                  />
                </div>
                <div>
                  <label className="text-xs text-muted-foreground mb-1 block">Currency</label>
                  <Input
                    placeholder="EUR"
                    value={currency}
                    onChange={(e) => setCurrency(e.target.value)}
                    maxLength={3}
                  />
                </div>
              </div>
              <textarea
                placeholder="Notes (optional)"
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                rows={2}
                className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <div className="flex justify-end gap-2">
                <Button type="button" variant="ghost" size="sm" onClick={() => setShowForm(false)}>Cancel</Button>
                <Button type="submit" size="sm" disabled={saving}>
                  {saving && <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />}
                  {editId ? 'Save changes' : 'Log defect'}
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}

interface DefectCardProps {
  defect: DefectLog
  roomName: string | null
  expanded: boolean
  onToggleExpand: () => void
  onEdit: () => void
  onDelete: () => void
  onMarkResolved: () => void
  onPhotosChange: (photos: string[]) => void
  property: Property
  deleting: boolean
  resolving: boolean
}

function DefectCard({ defect: d, roomName, expanded, onToggleExpand, onEdit, onDelete, onMarkResolved, onPhotosChange, property, deleting, resolving }: DefectCardProps) {
  const sevColor = SEVERITY_COLORS[d.severity] ?? 'hsl(0,0%,50%)'
  const statusColor = STATUS_COLORS[d.status] ?? 'hsl(0,0%,50%)'

  async function updatePhotos(photos: string[]) {
    onPhotosChange(photos)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any)
      .from('defect_logs')
      .update({ photo_urls: photos })
      .eq('id', d.id)
  }

  function handlePhotoAdd(path: string) {
    const updated = [...(d.photo_urls ?? []), path]
    void updatePhotos(updated)
  }

  function handlePhotoRemove(path: string) {
    const updated = (d.photo_urls ?? []).filter((p) => p !== path)
    void updatePhotos(updated)
  }

  return (
    <Card className="p-4 flex flex-col gap-3">
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-2 min-w-0 cursor-pointer" onClick={onToggleExpand}>
          <div
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg"
            style={{ background: `${sevColor}20`, color: sevColor }}
          >
            <Bug className="h-4 w-4" />
          </div>
          <div className="min-w-0">
            <p className="font-semibold text-sm truncate">{d.title}</p>
            <div className="flex items-center gap-1.5 flex-wrap mt-0.5">
              {roomName && <span className="text-xs text-muted-foreground">{roomName}</span>}
              <span className="text-xs text-muted-foreground">{fmtDate(d.reported_date)}</span>
              {d.cost != null && (
                <span className="text-xs text-muted-foreground">{d.currency ?? 'EUR'} {d.cost.toLocaleString()}</span>
              )}
            </div>
          </div>
        </div>
        <div className="flex items-center gap-1 shrink-0">
          {d.status !== 'resolved' && (
            <button
              onClick={onMarkResolved}
              disabled={resolving}
              title="Mark resolved"
              className="p-1.5 rounded-lg hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
            >
              {resolving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <CheckCircle className="h-3.5 w-3.5" />}
            </button>
          )}
          <button onClick={onEdit} className="p-1.5 rounded-lg hover:bg-muted transition-colors text-muted-foreground hover:text-foreground">
            <Pencil className="h-3.5 w-3.5" />
          </button>
          <button
            onClick={onDelete}
            disabled={deleting}
            className="p-1.5 rounded-lg hover:bg-destructive/10 transition-colors text-muted-foreground hover:text-destructive"
          >
            {deleting ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />}
          </button>
          <button onClick={onToggleExpand} className="p-1.5 rounded-lg hover:bg-muted transition-colors text-muted-foreground">
            {expanded ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
          </button>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <Badge
          variant="neutral"
          size="xs"
          className="capitalize"
          style={{ color: sevColor, borderColor: `${sevColor}44`, background: `${sevColor}18` }}
        >
          {d.severity}
        </Badge>
        <Badge
          variant="neutral"
          size="xs"
          style={{ color: statusColor, borderColor: `${statusColor}44`, background: `${statusColor}18` }}
        >
          {d.status.replace('_', ' ').replace(/\b\w/g, (c) => c.toUpperCase())}
        </Badge>
        {d.resolved_date && (
          <span className="text-xs text-muted-foreground">Resolved: {fmtDate(d.resolved_date)}</span>
        )}
      </div>

      {expanded && (
        <div className="space-y-3 pt-1 border-t border-border/30">
          {d.description && (
            <p className="text-xs text-muted-foreground">{d.description}</p>
          )}
          {d.notes && (
            <p className="text-xs text-muted-foreground italic">{d.notes}</p>
          )}
          <div className="space-y-1.5">
            <div className="flex items-center gap-1.5">
              <ImageIcon className="h-3.5 w-3.5 text-muted-foreground" />
              <p className="text-xs font-medium text-muted-foreground">Photos</p>
            </div>
            <PhotoGallery
              photos={d.photo_urls ?? []}
              onAdd={handlePhotoAdd}
              onRemove={handlePhotoRemove}
              propertyId={property.id}
              itemType="defect"
              itemId={d.id}
            />
          </div>
        </div>
      )}
    </Card>
  )
}
