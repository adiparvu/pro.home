'use client'

import * as React from 'react'
import { Webhook, Plus, X, Loader2, ToggleLeft, Trash2, Copy, RefreshCw, Clock } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import type { Property } from '@/lib/supabase/types'

interface OutboundWebhook {
  id: string
  property_id: string
  url: string
  events: string[]
  secret: string | null
  active: boolean
  last_triggered_at: string | null
  last_status_code: number | null
  created_at: string
}

interface IntegrationSettingsProps {
  property: Property
  userId: string
  memberRole: string
  initialWebhooks: OutboundWebhook[]
}

const WEBHOOK_EVENTS = [
  'task.created', 'task.completed', 'task.overdue',
  'finance.created', 'document.uploaded',
  'notification.critical', 'member.joined',
]

const CRON_JOBS = [
  { name: 'prv-notification-sweep', label: 'Notification sweep', schedule: 'Daily at 06:00 UTC', description: 'Marks overdue tasks and generates notifications' },
  { name: 'prv-weekly-digest',      label: 'Weekly digest',       schedule: 'Monday at 07:00 UTC', description: 'Sends weekly property digest emails' },
  { name: 'prv-recurring-finances', label: 'Recurring finances',  schedule: 'Daily at 05:30 UTC', description: 'Creates recurring financial records' },
]

function fmtDate(d: string | null) {
  if (!d) return 'Never'
  return new Date(d).toLocaleDateString('en', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
}

export function IntegrationSettings({ property, userId, memberRole, initialWebhooks }: IntegrationSettingsProps) {
  const confirmDialog = useConfirm()
  const [webhooks, setWebhooks] = React.useState<OutboundWebhook[]>(initialWebhooks)
  const [showForm, setShowForm] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [url, setUrl] = React.useState('')
  const [secret, setSecret] = React.useState('')
  const [selectedEvents, setSelectedEvents] = React.useState<string[]>([])
  const isOwner = memberRole === 'owner' || memberRole === 'partner'

  function toggleEvent(evt: string) {
    setSelectedEvents((prev) =>
      prev.includes(evt) ? prev.filter((e) => e !== evt) : [...prev, evt]
    )
  }

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault()
    if (!url.trim() || selectedEvents.length === 0) return
    setSaving(true)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('outbound_webhooks')
        .insert({
          property_id: property.id,
          url: url.trim(),
          events: selectedEvents,
          secret: secret.trim() || null,
          active: true,
          created_by: userId,
        })
        .select()
        .single()
      if (error) throw error
      setWebhooks((prev) => [data, ...prev])
      setUrl(''); setSecret(''); setSelectedEvents([])
      setShowForm(false)
      toast({ title: 'Webhook added' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  async function handleToggle(wh: OutboundWebhook) {
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('outbound_webhooks').update({ active: !wh.active }).eq('id', wh.id)
    setWebhooks((prev) => prev.map((w) => w.id === wh.id ? { ...w, active: !w.active } : w))
  }

  async function handleDelete(wh: OutboundWebhook) {
    const ok = await confirmDialog({ title: 'Delete webhook', description: 'This cannot be undone.', confirmLabel: 'Delete', destructive: true })
    if (!ok) return
    setDeletingId(wh.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('outbound_webhooks').delete().eq('id', wh.id)
      setWebhooks((prev) => prev.filter((w) => w.id !== wh.id))
    } finally {
      setDeletingId(null)
    }
  }

  return (
    <>
      <PageHeader title="Integrations" description="Webhooks & automation" />

      <div className="flex flex-col gap-6 px-4 py-4 md:px-6 md:py-6">
        {/* Webhook section */}
        <section>
          <div className="flex items-center justify-between mb-3">
            <div>
              <h2 className="text-sm font-semibold">Outbound Webhooks</h2>
              <p className="text-xs text-muted-foreground">POST events to external services</p>
            </div>
            {isOwner && (
              <Button size="sm" onClick={() => setShowForm(true)}>
                <Plus className="h-3.5 w-3.5 mr-1" />Add webhook
              </Button>
            )}
          </div>

          {webhooks.length === 0 ? (
            <Card className="p-6 text-center">
              <Webhook className="h-8 w-8 mx-auto text-muted-foreground opacity-30 mb-2" />
              <p className="text-sm text-muted-foreground">No webhooks configured</p>
              {isOwner && (
                <Button size="sm" className="mt-3" onClick={() => setShowForm(true)}>Add first webhook</Button>
              )}
            </Card>
          ) : (
            <div className="space-y-2">
              {webhooks.map((wh) => (
                <Card key={wh.id} className="p-4 flex items-start gap-3">
                  <div className={cn('mt-0.5 h-2 w-2 rounded-full shrink-0', wh.active ? 'bg-green-500' : 'bg-muted-foreground')} />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-mono truncate">{wh.url}</p>
                    <div className="flex flex-wrap gap-1 mt-1">
                      {wh.events.map((ev) => (
                        <span key={ev} className="text-[10px] px-1.5 py-0.5 rounded bg-muted text-muted-foreground">{ev}</span>
                      ))}
                    </div>
                    <p className="text-xs text-muted-foreground mt-1">
                      Last triggered: {fmtDate(wh.last_triggered_at)}
                      {wh.last_status_code != null && ` (${wh.last_status_code})`}
                    </p>
                  </div>
                  {isOwner && (
                    <div className="flex items-center gap-1 shrink-0">
                      <button onClick={() => handleToggle(wh)} className="p-1.5 text-muted-foreground hover:text-foreground transition-colors" title={wh.active ? 'Disable' : 'Enable'}>
                        <ToggleLeft className="h-3.5 w-3.5" />
                      </button>
                      <button onClick={() => handleDelete(wh)} disabled={deletingId === wh.id} className="p-1.5 text-muted-foreground hover:text-destructive transition-colors">
                        {deletingId === wh.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />}
                      </button>
                    </div>
                  )}
                </Card>
              ))}
            </div>
          )}
        </section>

        {/* Scheduled jobs section */}
        <section>
          <div className="mb-3">
            <h2 className="text-sm font-semibold">Scheduled Jobs</h2>
            <p className="text-xs text-muted-foreground">Background pg_cron tasks running on your database</p>
          </div>
          <div className="space-y-2">
            {CRON_JOBS.map((job) => (
              <Card key={job.name} className="p-4 flex items-start gap-3">
                <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/10 text-primary shrink-0">
                  <Clock className="h-4 w-4" />
                </div>
                <div className="flex-1">
                  <p className="text-sm font-medium">{job.label}</p>
                  <p className="text-xs text-muted-foreground">{job.description}</p>
                  <p className="text-xs text-muted-foreground/60 mt-0.5 font-mono">{job.schedule}</p>
                </div>
                <div className="h-2 w-2 rounded-full bg-green-500 mt-1 shrink-0" title="Running" />
              </Card>
            ))}
          </div>
        </section>

        {/* Zapier hint */}
        <Card className="p-4 flex items-center gap-3 border-dashed">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-orange-500/10 text-orange-500 shrink-0">
            <RefreshCw className="h-4 w-4" />
          </div>
          <div>
            <p className="text-sm font-medium">Connect Zapier / Make</p>
            <p className="text-xs text-muted-foreground">Use the webhook URL above with Zapier or Make to trigger 5000+ automations</p>
          </div>
        </Card>
      </div>

      {showForm && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-md p-5 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">Add Webhook</h2>
              <button onClick={() => setShowForm(false)}><X className="h-4 w-4 text-muted-foreground" /></button>
            </div>
            <form onSubmit={handleAdd} className="space-y-3">
              <Input placeholder="Endpoint URL *" type="url" value={url} onChange={(e) => setUrl(e.target.value)} required />
              <Input placeholder="Secret (for HMAC signature, optional)" value={secret} onChange={(e) => setSecret(e.target.value)} />
              <div>
                <p className="text-xs text-muted-foreground mb-2">Events to send *</p>
                <div className="grid grid-cols-2 gap-1.5">
                  {WEBHOOK_EVENTS.map((ev) => (
                    <label key={ev} className="flex items-center gap-2 text-xs cursor-pointer">
                      <input
                        type="checkbox"
                        checked={selectedEvents.includes(ev)}
                        onChange={() => toggleEvent(ev)}
                        className="rounded"
                      />
                      {ev}
                    </label>
                  ))}
                </div>
              </div>
              <div className="flex justify-end gap-2">
                <Button type="button" variant="ghost" size="sm" onClick={() => setShowForm(false)}>Cancel</Button>
                <Button type="submit" size="sm" disabled={saving || selectedEvents.length === 0}>
                  {saving && <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />}
                  Add webhook
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}
