'use client'

import * as React from 'react'
import {
  FolderKanban, Plus, Calendar, DollarSign, CheckSquare, ChevronRight,
  Pencil, Trash2, X, Loader2, Target, Clock, CheckCircle2,
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

interface Project {
  id: string
  property_id: string
  title: string
  description: string | null
  status: 'planning' | 'active' | 'on_hold' | 'completed' | 'cancelled'
  budget: number | null
  spent: number | null
  start_date: string | null
  end_date: string | null
  room_id: string | null
  created_at: string
  rooms?: { name: string } | null
}

interface TaskCount {
  project_id: string
  status: string
}

interface ProjectsPageProps {
  property: Property
  initialProjects: Project[]
  taskCounts: TaskCount[]
}

const STATUS_CONFIG: Record<Project['status'], { label: string; color: string; icon: React.ComponentType<{ className?: string }> }> = {
  planning:  { label: 'Planning',   color: 'hsl(220,62%,52%)', icon: Target },
  active:    { label: 'Active',     color: 'hsl(152,62%,42%)', icon: Clock },
  on_hold:   { label: 'On Hold',    color: 'hsl(45,75%,42%)',  icon: Clock },
  completed: { label: 'Completed',  color: 'hsl(152,62%,38%)', icon: CheckCircle2 },
  cancelled: { label: 'Cancelled',  color: 'hsl(0,0%,50%)',    icon: X },
}

function formatMoney(v: number | null) {
  if (v == null) return '—'
  return `€${v.toLocaleString('en', { maximumFractionDigits: 0 })}`
}

export function ProjectsPage({ property, initialProjects, taskCounts }: ProjectsPageProps) {
  const confirmDialog = useConfirm()
  const [projects, setProjects] = React.useState<Project[]>(initialProjects)
  const [statusFilter, setStatusFilter] = React.useState<Project['status'] | 'all'>('all')
  const [showForm, setShowForm] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)

  const [title, setTitle] = React.useState('')
  const [description, setDescription] = React.useState('')
  const [status, setStatus] = React.useState<Project['status']>('planning')
  const [budget, setBudget] = React.useState('')
  const [startDate, setStartDate] = React.useState('')
  const [endDate, setEndDate] = React.useState('')
  const [editId, setEditId] = React.useState<string | null>(null)

  const taskCountsByProject = React.useMemo(() => {
    const map: Record<string, { total: number; done: number }> = {}
    for (const t of taskCounts) {
      if (!t.project_id) continue
      if (!map[t.project_id]) map[t.project_id] = { total: 0, done: 0 }
      // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
      map[t.project_id]!.total++
      // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
      if (t.status === 'completed') map[t.project_id]!.done++
    }
    return map
  }, [taskCounts])

  const filtered = statusFilter === 'all' ? projects : projects.filter((p) => p.status === statusFilter)

  function openNew() {
    setEditId(null)
    setTitle(''); setDescription(''); setStatus('planning')
    setBudget(''); setStartDate(''); setEndDate('')
    setShowForm(true)
  }

  function openEdit(p: Project) {
    setEditId(p.id)
    setTitle(p.title); setDescription(p.description ?? '')
    setStatus(p.status); setBudget(p.budget ? String(p.budget) : '')
    setStartDate(p.start_date ?? ''); setEndDate(p.end_date ?? '')
    setShowForm(true)
  }

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    if (!title.trim()) return
    setSaving(true)
    try {
      const supabase = createClient()
      const payload = {
        title: title.trim(),
        description: description.trim() || null,
        status,
        budget: budget ? parseFloat(budget) : null,
        start_date: startDate || null,
        end_date: endDate || null,
        property_id: property.id,
      }
      if (editId) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data, error } = await (supabase as any)
          .from('projects').update(payload).eq('id', editId).select().single()
        if (error) throw error
        setProjects((prev) => prev.map((p) => (p.id === editId ? data : p)))
        toast({ title: 'Project updated' })
      } else {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data, error } = await (supabase as any)
          .from('projects').insert(payload).select().single()
        if (error) throw error
        setProjects((prev) => [data, ...prev])
        toast({ title: 'Project created' })
      }
      setShowForm(false)
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete(p: Project) {
    const ok = await confirmDialog({
      title: 'Delete project',
      description: `Delete "${p.title}"? Tasks linked to it will be unlinked.`,
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(p.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('projects').delete().eq('id', p.id)
      setProjects((prev) => prev.filter((x) => x.id !== p.id))
      toast({ title: 'Project deleted' })
    } finally {
      setDeletingId(null)
    }
  }

  const statusTotals = React.useMemo(() => {
    const map: Record<string, number> = { all: projects.length }
    for (const p of projects) map[p.status] = (map[p.status] ?? 0) + 1
    return map
  }, [projects])

  return (
    <>
      <PageHeader
        title="Projects"
        description={property.name}
        action={{ label: 'New Project', href: '#', onClick: openNew }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Status filter */}
        <div className="flex gap-2 flex-wrap">
          {(['all', 'planning', 'active', 'on_hold', 'completed', 'cancelled'] as const).map((s) => (
            <button
              key={s}
              onClick={() => setStatusFilter(s)}
              className={cn(
                'px-3 py-1 rounded-full text-xs font-medium border transition-colors',
                statusFilter === s
                  ? 'bg-primary text-white border-primary'
                  : 'border-border/50 text-muted-foreground hover:text-foreground'
              )}
            >
              {s === 'all' ? 'All' : STATUS_CONFIG[s].label}
              {statusTotals[s] != null && (
                <span className="ml-1 opacity-60">({statusTotals[s]})</span>
              )}
            </button>
          ))}
        </div>

        {/* Project cards */}
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
            <FolderKanban className="h-10 w-10 opacity-30" />
            <p className="text-sm">No projects yet</p>
            <Button size="sm" onClick={openNew}><Plus className="h-4 w-4 mr-1" />New Project</Button>
          </div>
        ) : (
          <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
            {filtered.map((p) => {
              const cfg = STATUS_CONFIG[p.status]
              const StatusIcon = cfg.icon
              const tc = taskCountsByProject[p.id]
              const spentPct = p.budget && p.spent ? Math.min(100, (p.spent / p.budget) * 100) : null

              return (
                <Card key={p.id} className="p-4 flex flex-col gap-3">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-center gap-2 min-w-0">
                      <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg" style={{ background: cfg.color + '20', color: cfg.color }}>
                        <StatusIcon className="h-4 w-4" />
                      </div>
                      <div className="min-w-0">
                        <p className="font-semibold text-sm truncate">{p.title}</p>
                        {p.rooms?.name && (
                          <p className="text-xs text-muted-foreground">{p.rooms.name}</p>
                        )}
                      </div>
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      <button onClick={() => openEdit(p)} className="p-1.5 rounded-lg hover:bg-muted transition-colors text-muted-foreground hover:text-foreground">
                        <Pencil className="h-3.5 w-3.5" />
                      </button>
                      <button
                        onClick={() => handleDelete(p)}
                        disabled={deletingId === p.id}
                        className="p-1.5 rounded-lg hover:bg-destructive/10 transition-colors text-muted-foreground hover:text-destructive"
                      >
                        {deletingId === p.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />}
                      </button>
                    </div>
                  </div>

                  {p.description && (
                    <p className="text-xs text-muted-foreground line-clamp-2">{p.description}</p>
                  )}

                  <div className="flex flex-wrap gap-2 text-xs text-muted-foreground">
                    {p.start_date && (
                      <span className="flex items-center gap-1">
                        <Calendar className="h-3 w-3" />
                        {p.start_date}{p.end_date ? ` → ${p.end_date}` : ''}
                      </span>
                    )}
                    {p.budget != null && (
                      <span className="flex items-center gap-1">
                        <DollarSign className="h-3 w-3" />
                        {formatMoney(p.budget)} budget
                      </span>
                    )}
                    {tc && (
                      <span className="flex items-center gap-1">
                        <CheckSquare className="h-3 w-3" />
                        {tc.done}/{tc.total} tasks
                      </span>
                    )}
                  </div>

                  {/* Budget progress */}
                  {spentPct != null && (
                    <div className="space-y-1">
                      <div className="flex justify-between text-xs text-muted-foreground">
                        <span>Spent: {formatMoney(p.spent)}</span>
                        <span>{spentPct.toFixed(0)}%</span>
                      </div>
                      <div className="h-1.5 rounded-full bg-muted overflow-hidden">
                        <div
                          className="h-full rounded-full transition-all"
                          style={{
                            width: `${spentPct}%`,
                            background: spentPct > 90 ? 'hsl(0,68%,44%)' : cfg.color,
                          }}
                        />
                      </div>
                    </div>
                  )}

                  {/* Task progress */}
                  {tc && tc.total > 0 && (
                    <div className="h-1 rounded-full bg-muted overflow-hidden">
                      <div
                        className="h-full rounded-full bg-primary transition-all"
                        style={{ width: `${(tc.done / tc.total) * 100}%` }}
                      />
                    </div>
                  )}
                </Card>
              )
            })}
          </div>
        )}
      </div>

      {/* New/Edit form modal */}
      {showForm && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-lg p-5 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">{editId ? 'Edit Project' : 'New Project'}</h2>
              <button onClick={() => setShowForm(false)} className="text-muted-foreground hover:text-foreground">
                <X className="h-4 w-4" />
              </button>
            </div>
            <form onSubmit={handleSave} className="space-y-3">
              <Input placeholder="Project title *" value={title} onChange={(e) => setTitle(e.target.value)} required />
              <textarea
                placeholder="Description (optional)"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                rows={2}
                className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <div className="grid grid-cols-2 gap-3">
                <select
                  value={status}
                  onChange={(e) => setStatus(e.target.value as Project['status'])}
                  className="rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                >
                  {Object.entries(STATUS_CONFIG).map(([k, v]) => (
                    <option key={k} value={k}>{v.label}</option>
                  ))}
                </select>
                <Input placeholder="Budget (€)" type="number" min="0" step="0.01" value={budget} onChange={(e) => setBudget(e.target.value)} />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs text-muted-foreground">Start date</label>
                  <Input type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
                </div>
                <div>
                  <label className="text-xs text-muted-foreground">End date</label>
                  <Input type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
                </div>
              </div>
              <div className="flex justify-end gap-2">
                <Button type="button" variant="ghost" size="sm" onClick={() => setShowForm(false)}>Cancel</Button>
                <Button type="submit" size="sm" disabled={saving}>
                  {saving && <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />}
                  {editId ? 'Save changes' : 'Create project'}
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}
