'use client'

import * as React from 'react'
import { Cpu, Plus, X, Loader2, AlertTriangle, Info, AlertCircle, Zap, Trash2 } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import type { Property } from '@/lib/supabase/types'

interface SmartHomeEvent {
  id: string
  property_id: string
  device_name: string
  event_type: 'status_change' | 'alert' | 'reading' | 'maintenance' | 'firmware' | 'other'
  severity: 'info' | 'warning' | 'alert' | 'critical'
  value: string | null
  notes: string | null
  logged_by: string | null
  created_at: string
}

interface SmartHomePageProps {
  property: Property
  userId: string
  initialEvents: SmartHomeEvent[]
}

const SEVERITY_CONFIG = {
  info:     { label: 'Info',     color: 'hsl(220,62%,52%)', icon: Info },
  warning:  { label: 'Warning',  color: 'hsl(45,75%,42%)',  icon: AlertTriangle },
  alert:    { label: 'Alert',    color: 'hsl(22,68%,45%)',  icon: AlertCircle },
  critical: { label: 'Critical', color: 'hsl(0,68%,44%)',   icon: Zap },
}

const EVENT_TYPES = ['status_change','alert','reading','maintenance','firmware','other'] as const

function fmtTime(dt: string) {
  const d = new Date(dt)
  return d.toLocaleDateString('en', { month: 'short', day: 'numeric' }) + ' ' +
    d.toLocaleTimeString('en', { hour: '2-digit', minute: '2-digit' })
}

export function SmartHomePage({ property, userId, initialEvents }: SmartHomePageProps) {
  const confirmDialog = useConfirm()
  const [events, setEvents] = React.useState<SmartHomeEvent[]>(initialEvents)
  const [severityFilter, setSeverityFilter] = React.useState<SmartHomeEvent['severity'] | 'all'>('all')
  const [deviceFilter, setDeviceFilter] = React.useState('')
  const [showForm, setShowForm] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)

  const [deviceName, setDeviceName] = React.useState('')
  const [eventType, setEventType] = React.useState<SmartHomeEvent['event_type']>('status_change')
  const [severity, setSeverity] = React.useState<SmartHomeEvent['severity']>('info')
  const [value, setValue] = React.useState('')
  const [notes, setNotes] = React.useState('')

  const devices = React.useMemo(() =>
    Array.from(new Set(events.map((e) => e.device_name))).sort(), [events])

  const filtered = events.filter((e) => {
    if (severityFilter !== 'all' && e.severity !== severityFilter) return false
    if (deviceFilter && e.device_name !== deviceFilter) return false
    return true
  })

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault()
    if (!deviceName.trim()) return
    setSaving(true)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('smart_home_events')
        .insert({
          property_id: property.id,
          device_name: deviceName.trim(),
          event_type: eventType,
          severity,
          value: value.trim() || null,
          notes: notes.trim() || null,
          logged_by: userId,
        })
        .select()
        .single()
      if (error) throw error
      setEvents((prev) => [data, ...prev])
      setDeviceName(''); setValue(''); setNotes('')
      setShowForm(false)
      toast({ title: 'Event logged' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete(evt: SmartHomeEvent) {
    const ok = await confirmDialog({ title: 'Delete event', description: 'Remove this log entry?', confirmLabel: 'Delete', destructive: true })
    if (!ok) return
    setDeletingId(evt.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('smart_home_events').delete().eq('id', evt.id)
      setEvents((prev) => prev.filter((x) => x.id !== evt.id))
    } finally {
      setDeletingId(null)
    }
  }

  const severityCounts: Record<string, number> = React.useMemo(() => {
    const m: Record<string, number> = { all: events.length }
    for (const e of events) m[e.severity] = (m[e.severity] ?? 0) + 1
    return m
  }, [events])

  return (
    <>
      <PageHeader
        title="Smart Home Log"
        description={property.name}
        action={{ label: 'Log Event', href: '#', onClick: () => setShowForm(true) }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Severity filter */}
        <div className="flex gap-2 flex-wrap">
          {(['all', 'info', 'warning', 'alert', 'critical'] as const).map((s) => (
            <button
              key={s}
              onClick={() => setSeverityFilter(s)}
              className={cn(
                'px-3 py-1 rounded-full text-xs font-medium border transition-colors',
                severityFilter === s
                  ? 'bg-primary text-white border-primary'
                  : 'border-border/50 text-muted-foreground hover:text-foreground'
              )}
            >
              {s === 'all' ? 'All' : SEVERITY_CONFIG[s].label}
              {severityCounts[s] != null && <span className="ml-1 opacity-60">({severityCounts[s]})</span>}
            </button>
          ))}
        </div>

        {/* Device filter */}
        {devices.length > 1 && (
          <div className="flex gap-2 flex-wrap">
            <button
              onClick={() => setDeviceFilter('')}
              className={cn('px-3 py-1 rounded-full text-xs border transition-colors', !deviceFilter ? 'bg-muted border-border' : 'border-border/50 text-muted-foreground')}
            >
              All devices
            </button>
            {devices.map((d) => (
              <button
                key={d}
                onClick={() => setDeviceFilter(d === deviceFilter ? '' : d)}
                className={cn('px-3 py-1 rounded-full text-xs border transition-colors', deviceFilter === d ? 'bg-muted border-border' : 'border-border/50 text-muted-foreground')}
              >
                {d}
              </button>
            ))}
          </div>
        )}

        {/* Events list */}
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
            <Cpu className="h-10 w-10 opacity-30" />
            <p className="text-sm">No events logged yet</p>
            <Button size="sm" onClick={() => setShowForm(true)}><Plus className="h-4 w-4 mr-1" />Log first event</Button>
          </div>
        ) : (
          <Card className="p-0 overflow-hidden">
            <div className="divide-y divide-border/30">
              {filtered.map((evt) => {
                const cfg = SEVERITY_CONFIG[evt.severity]
                const SevIcon = cfg.icon
                return (
                  <div key={evt.id} className="flex items-start gap-3 px-4 py-3">
                    <div
                      className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg mt-0.5"
                      style={{ background: cfg.color + '20', color: cfg.color }}
                    >
                      <SevIcon className="h-4 w-4" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <p className="text-sm font-medium">{evt.device_name}</p>
                        <Badge variant="neutral" style={{ borderColor: cfg.color + '60', color: cfg.color }} className="text-[10px] px-1.5 py-0 !border-[var(--sev-color)]" data-sev-color={cfg.color}>
                          {cfg.label}
                        </Badge>
                        <span className="text-xs text-muted-foreground capitalize">{evt.event_type.replace(/_/g, ' ')}</span>
                      </div>
                      {evt.value && <p className="text-xs text-muted-foreground mt-0.5">Value: {evt.value}</p>}
                      {evt.notes && <p className="text-xs text-muted-foreground mt-0.5">{evt.notes}</p>}
                      <p className="text-xs text-muted-foreground/60 mt-0.5">{fmtTime(evt.created_at)}</p>
                    </div>
                    <button
                      onClick={() => handleDelete(evt)}
                      disabled={deletingId === evt.id}
                      className="shrink-0 p-1.5 text-muted-foreground hover:text-destructive transition-colors"
                    >
                      {deletingId === evt.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />}
                    </button>
                  </div>
                )
              })}
            </div>
          </Card>
        )}
      </div>

      {showForm && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-md p-5 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">Log Smart Home Event</h2>
              <button onClick={() => setShowForm(false)}><X className="h-4 w-4 text-muted-foreground" /></button>
            </div>
            <form onSubmit={handleAdd} className="space-y-3">
              <Input placeholder="Device name *" value={deviceName} onChange={(e) => setDeviceName(e.target.value)} list="device-suggestions" required />
              <datalist id="device-suggestions">
                {devices.map((d) => <option key={d} value={d} />)}
              </datalist>
              <div className="grid grid-cols-2 gap-3">
                <select value={eventType} onChange={(e) => setEventType(e.target.value as SmartHomeEvent['event_type'])} className="rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30">
                  {EVENT_TYPES.map((t) => <option key={t} value={t}>{t.replace(/_/g, ' ')}</option>)}
                </select>
                <select value={severity} onChange={(e) => setSeverity(e.target.value as SmartHomeEvent['severity'])} className="rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30">
                  {Object.entries(SEVERITY_CONFIG).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
                </select>
              </div>
              <Input placeholder="Value / reading (optional)" value={value} onChange={(e) => setValue(e.target.value)} />
              <textarea placeholder="Notes (optional)" value={notes} onChange={(e) => setNotes(e.target.value)} rows={2} className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30" />
              <div className="flex justify-end gap-2">
                <Button type="button" variant="ghost" size="sm" onClick={() => setShowForm(false)}>Cancel</Button>
                <Button type="submit" size="sm" disabled={saving}>
                  {saving && <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />}
                  Log event
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}
