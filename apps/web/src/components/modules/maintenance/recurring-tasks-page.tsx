'use client'

import * as React from 'react'
import { RotateCcw, Plus, Pencil, Trash2, X, Loader2, PlayCircle } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import type { Property } from '@/lib/supabase/types'

interface RecurringTemplate {
  id: string
  property_id: string
  title: string
  description: string | null
  category: string | null
  priority: string | null
  interval_days: number
  last_created_at: string | null
  next_due_date: string | null
  active: boolean
  created_by: string | null
  created_at: string
  updated_at: string
}

interface RecurringTasksPageProps {
  property: Property
  userId: string
  initialTemplates: RecurringTemplate[]
}

const CATEGORIES = ['maintenance', 'repair', 'inspection', 'cleaning', 'upgrade', 'administrative', 'other']
const PRIORITIES = ['critical', 'high', 'medium', 'low']

const PRIORITY_COLORS: Record<string, string> = {
  critical: 'hsl(0,68%,44%)',
  high: 'hsl(22,68%,41%)',
  medium: 'hsl(45,75%,42%)',
  low: 'hsl(210,75%,42%)',
}

function fmtDate(d: string | null) {
  if (!d) return '—'
  return new Date(d).toLocaleDateString('en', { day: 'numeric', month: 'short', year: 'numeric' })
}

function intervalLabel(days: number): string {
  if (days === 1) return 'Daily'
  if (days === 7) return 'Weekly'
  if (days === 14) return 'Every 2 weeks'
  if (days === 30) return 'Monthly'
  if (days === 90) return 'Quarterly'
  if (days === 180) return 'Every 6 months'
  if (days === 365) return 'Yearly'
  return `Every ${days} days`
}

export function RecurringTasksPage({ property, userId, initialTemplates }: RecurringTasksPageProps) {
  const confirmDialog = useConfirm()
  const [templates, setTemplates] = React.useState<RecurringTemplate[]>(initialTemplates)
  const [showForm, setShowForm] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [togglingId, setTogglingId] = React.useState<string | null>(null)
  const [creatingTaskId, setCreatingTaskId] = React.useState<string | null>(null)
  const [editId, setEditId] = React.useState<string | null>(null)

  // Form state
  const [title, setTitle] = React.useState('')
  const [description, setDescription] = React.useState('')
  const [category, setCategory] = React.useState('maintenance')
  const [priority, setPriority] = React.useState('medium')
  const [intervalDays, setIntervalDays] = React.useState('30')

  function openNew() {
    setEditId(null)
    setTitle('')
    setDescription('')
    setCategory('maintenance')
    setPriority('medium')
    setIntervalDays('30')
    setShowForm(true)
  }

  function openEdit(t: RecurringTemplate) {
    setEditId(t.id)
    setTitle(t.title)
    setDescription(t.description ?? '')
    setCategory(t.category ?? 'maintenance')
    setPriority(t.priority ?? 'medium')
    setIntervalDays(String(t.interval_days))
    setShowForm(true)
  }

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    if (!title.trim()) return
    const days = parseInt(intervalDays)
    if (isNaN(days) || days < 1) {
      toast({ title: 'Interval must be at least 1 day', variant: 'destructive' })
      return
    }
    setSaving(true)
    try {
      const supabase = createClient()
      const now = new Date()
      const nextDue = new Date(now.getTime() + days * 86400000).toISOString().split('T')[0]
      const payload = {
        property_id: property.id,
        title: title.trim(),
        description: description.trim() || null,
        category,
        priority,
        interval_days: days,
        active: true,
        next_due_date: nextDue,
        created_by: userId,
      }
      if (editId) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data, error } = await (supabase as any)
          .from('recurring_task_templates')
          .update({ title: payload.title, description: payload.description, category, priority, interval_days: days })
          .eq('id', editId)
          .select()
          .single()
        if (error) throw error
        setTemplates((prev) => prev.map((t) => (t.id === editId ? data : t)))
        toast({ title: 'Template updated' })
      } else {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data, error } = await (supabase as any)
          .from('recurring_task_templates')
          .insert(payload)
          .select()
          .single()
        if (error) throw error
        setTemplates((prev) => [data, ...prev])
        toast({ title: 'Template created' })
      }
      setShowForm(false)
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete(t: RecurringTemplate) {
    const ok = await confirmDialog({
      title: 'Delete template',
      description: `Delete "${t.title}"? This cannot be undone.`,
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(t.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('recurring_task_templates').delete().eq('id', t.id)
      setTemplates((prev) => prev.filter((x) => x.id !== t.id))
      toast({ title: 'Template deleted' })
    } finally {
      setDeletingId(null)
    }
  }

  async function handleToggleActive(t: RecurringTemplate) {
    setTogglingId(t.id)
    try {
      const supabase = createClient()
      const newActive = !t.active
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { error } = await (supabase as any)
        .from('recurring_task_templates')
        .update({ active: newActive })
        .eq('id', t.id)
      if (error) throw error
      setTemplates((prev) => prev.map((x) => (x.id === t.id ? { ...x, active: newActive } : x)))
      toast({ title: newActive ? 'Template activated' : 'Template deactivated' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setTogglingId(null)
    }
  }

  async function handleCreateTaskNow(t: RecurringTemplate) {
    setCreatingTaskId(t.id)
    try {
      const supabase = createClient()
      const now = new Date()
      const nextDue = new Date(now.getTime() + t.interval_days * 86400000).toISOString().split('T')[0]
      const dueDate = now.toISOString().split('T')[0]

      // Insert the maintenance task
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { error: taskError } = await (supabase as any)
        .from('maintenance_tasks')
        .insert({
          property_id: property.id,
          title: t.title,
          description: t.description,
          category: t.category,
          priority: t.priority ?? 'medium',
          status: 'pending',
          due_date: dueDate,
          created_by: userId,
        })
      if (taskError) throw taskError

      // Update template's last_created_at and next_due_date
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: updated, error: updateError } = await (supabase as any)
        .from('recurring_task_templates')
        .update({ last_created_at: now.toISOString(), next_due_date: nextDue })
        .eq('id', t.id)
        .select()
        .single()
      if (updateError) throw updateError

      setTemplates((prev) => prev.map((x) => (x.id === t.id ? updated : x)))
      toast({ title: 'Task created from template' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setCreatingTaskId(null)
    }
  }

  const active = templates.filter((t) => t.active)
  const inactive = templates.filter((t) => !t.active)

  return (
    <>
      <PageHeader
        title="Recurring Tasks"
        description={property.name}
        action={{ label: 'Add Template', href: '#', onClick: openNew }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {templates.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
            <RotateCcw className="h-10 w-10 opacity-30" />
            <p className="text-sm">No recurring templates yet</p>
            <Button size="sm" onClick={openNew}><Plus className="h-4 w-4 mr-1" />Add Template</Button>
          </div>
        ) : (
          <>
            {active.length > 0 && (
              <div className="space-y-2">
                <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Active ({active.length})</p>
                {active.map((t) => (
                  <TemplateCard
                    key={t.id}
                    template={t}
                    onEdit={() => openEdit(t)}
                    onDelete={() => handleDelete(t)}
                    onToggle={() => handleToggleActive(t)}
                    onCreateNow={() => handleCreateTaskNow(t)}
                    deleting={deletingId === t.id}
                    toggling={togglingId === t.id}
                    creatingTask={creatingTaskId === t.id}
                  />
                ))}
              </div>
            )}
            {inactive.length > 0 && (
              <div className="space-y-2">
                <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Inactive ({inactive.length})</p>
                {inactive.map((t) => (
                  <TemplateCard
                    key={t.id}
                    template={t}
                    onEdit={() => openEdit(t)}
                    onDelete={() => handleDelete(t)}
                    onToggle={() => handleToggleActive(t)}
                    onCreateNow={() => handleCreateTaskNow(t)}
                    deleting={deletingId === t.id}
                    toggling={togglingId === t.id}
                    creatingTask={creatingTaskId === t.id}
                  />
                ))}
              </div>
            )}
          </>
        )}
      </div>

      {/* Form modal */}
      {showForm && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-lg p-5 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">{editId ? 'Edit Template' : 'New Recurring Template'}</h2>
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
              <textarea
                placeholder="Description (optional)"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                rows={2}
                className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs text-muted-foreground mb-1 block">Category</label>
                  <select
                    value={category}
                    onChange={(e) => setCategory(e.target.value)}
                    className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                  >
                    {CATEGORIES.map((c) => (
                      <option key={c} value={c}>{c.charAt(0).toUpperCase() + c.slice(1)}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="text-xs text-muted-foreground mb-1 block">Priority</label>
                  <select
                    value={priority}
                    onChange={(e) => setPriority(e.target.value)}
                    className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                  >
                    {PRIORITIES.map((p) => (
                      <option key={p} value={p}>{p.charAt(0).toUpperCase() + p.slice(1)}</option>
                    ))}
                  </select>
                </div>
              </div>
              <div>
                <label className="text-xs text-muted-foreground mb-1 block">Interval (days) *</label>
                <Input
                  type="number"
                  min="1"
                  placeholder="e.g. 30 for monthly"
                  value={intervalDays}
                  onChange={(e) => setIntervalDays(e.target.value)}
                  required
                />
              </div>
              <div className="flex justify-end gap-2">
                <Button type="button" variant="ghost" size="sm" onClick={() => setShowForm(false)}>Cancel</Button>
                <Button type="submit" size="sm" disabled={saving}>
                  {saving && <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />}
                  {editId ? 'Save changes' : 'Create template'}
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}

interface TemplateCardProps {
  template: RecurringTemplate
  onEdit: () => void
  onDelete: () => void
  onToggle: () => void
  onCreateNow: () => void
  deleting: boolean
  toggling: boolean
  creatingTask: boolean
}

function TemplateCard({ template: t, onEdit, onDelete, onToggle, onCreateNow, deleting, toggling, creatingTask }: TemplateCardProps) {
  const priorityColor = t.priority ? (PRIORITY_COLORS[t.priority] ?? 'hsl(210,75%,42%)') : 'hsl(210,75%,42%)'

  return (
    <Card className={`p-4 flex flex-col gap-3 ${!t.active ? 'opacity-60' : ''}`}>
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-2 min-w-0">
          <div
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg"
            style={{ background: `${priorityColor}20`, color: priorityColor }}
          >
            <RotateCcw className="h-4 w-4" />
          </div>
          <div className="min-w-0">
            <p className="font-semibold text-sm truncate">{t.title}</p>
            <p className="text-xs text-muted-foreground">{intervalLabel(t.interval_days)}</p>
          </div>
        </div>
        <div className="flex items-center gap-1 shrink-0">
          <button onClick={onCreateNow} disabled={creatingTask} title="Create task now" className="p-1.5 rounded-lg hover:bg-muted transition-colors text-muted-foreground hover:text-foreground">
            {creatingTask ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <PlayCircle className="h-3.5 w-3.5" />}
          </button>
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
        </div>
      </div>

      {t.description && (
        <p className="text-xs text-muted-foreground line-clamp-2">{t.description}</p>
      )}

      <div className="flex flex-wrap items-center gap-2">
        {t.category && (
          <Badge variant="neutral" size="xs" className="capitalize">{t.category}</Badge>
        )}
        {t.priority && (
          <Badge variant="neutral" size="xs" className="capitalize" style={{ color: priorityColor, borderColor: `${priorityColor}44`, background: `${priorityColor}18` }}>
            {t.priority}
          </Badge>
        )}
        {!t.active && <Badge variant="neutral" size="xs">Inactive</Badge>}
      </div>

      <div className="flex items-center justify-between">
        <div className="text-xs text-muted-foreground space-y-0.5">
          {t.last_created_at && <p>Last created: {fmtDate(t.last_created_at)}</p>}
          {t.next_due_date && <p>Next due: {fmtDate(t.next_due_date)}</p>}
        </div>
        <button
          onClick={onToggle}
          disabled={toggling}
          className="text-xs text-muted-foreground hover:text-foreground transition-colors underline underline-offset-2"
        >
          {toggling ? <Loader2 className="h-3 w-3 animate-spin inline" /> : (t.active ? 'Deactivate' : 'Activate')}
        </button>
      </div>
    </Card>
  )
}
