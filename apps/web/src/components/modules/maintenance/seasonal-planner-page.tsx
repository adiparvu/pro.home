'use client'

import * as React from 'react'
import { Sun, Snowflake, Leaf, Flower2, Plus, Trash2, X, Loader2, Zap } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import type { Property } from '@/lib/supabase/types'

interface SeasonalTemplate {
  id: string
  property_id: string
  season: Season
  title: string
  category: string | null
  description: string | null
  priority: string | null
  created_at: string
}

type Season = 'spring' | 'summer' | 'autumn' | 'winter'

interface SeasonalPlannerPageProps {
  property: Property
  userId: string
}

const SEASONS: Season[] = ['spring', 'summer', 'autumn', 'winter']

const SEASON_CONFIG: Record<Season, {
  label: string
  months: string
  monthRange: [number, number]
  Icon: React.ComponentType<{ className?: string; style?: React.CSSProperties }>
  color: string
}> = {
  spring: {
    label: 'Spring',
    months: 'Mar – May',
    monthRange: [2, 4],
    Icon: Flower2,
    color: 'hsl(120, 52%, 38%)',
  },
  summer: {
    label: 'Summer',
    months: 'Jun – Aug',
    monthRange: [5, 7],
    Icon: Sun,
    color: 'hsl(45, 75%, 42%)',
  },
  autumn: {
    label: 'Autumn',
    months: 'Sep – Nov',
    monthRange: [8, 10],
    Icon: Leaf,
    color: 'hsl(22, 68%, 41%)',
  },
  winter: {
    label: 'Winter',
    months: 'Dec – Feb',
    monthRange: [11, 1],
    Icon: Snowflake,
    color: 'hsl(210, 75%, 42%)',
  },
}

const CATEGORIES = ['maintenance', 'repair', 'inspection', 'cleaning', 'upgrade', 'administrative', 'other']
const PRIORITIES = ['low', 'normal', 'high']

const PRIORITY_COLORS: Record<string, string> = {
  high: 'hsl(0,68%,44%)',
  normal: 'hsl(210,75%,42%)',
  low: 'hsl(152,62%,38%)',
}

function getCurrentSeason(): Season {
  const month = new Date().getMonth() // 0-indexed
  if (month >= 2 && month <= 4) return 'spring'
  if (month >= 5 && month <= 7) return 'summer'
  if (month >= 8 && month <= 10) return 'autumn'
  return 'winter'
}

function getSeasonEndDate(season: Season): string {
  const year = new Date().getFullYear()
  const ends: Record<Season, string> = {
    spring: `${year}-05-31`,
    summer: `${year}-08-31`,
    autumn: `${year}-11-30`,
    winter: `${year + (new Date().getMonth() === 11 ? 1 : 0)}-02-28`,
  }
  return ends[season]
}

export function SeasonalPlannerPage({ property, userId }: SeasonalPlannerPageProps) {
  const confirmDialog = useConfirm()
  const currentSeason = getCurrentSeason()
  const [activeSeason, setActiveSeason] = React.useState<Season>(currentSeason)
  const [templates, setTemplates] = React.useState<SeasonalTemplate[]>([])
  const [loading, setLoading] = React.useState(true)
  const [showForm, setShowForm] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [generating, setGenerating] = React.useState(false)

  // Form state
  const [formTitle, setFormTitle] = React.useState('')
  const [formSeason, setFormSeason] = React.useState<Season>(currentSeason)
  const [formCategory, setFormCategory] = React.useState('maintenance')
  const [formPriority, setFormPriority] = React.useState('normal')
  const [formDescription, setFormDescription] = React.useState('')

  React.useEffect(() => {
    async function load() {
      setLoading(true)
      try {
        const supabase = createClient()
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data } = await (supabase as any)
          .from('seasonal_task_templates')
          .select('*')
          .eq('property_id', property.id)
          .order('created_at', { ascending: false })
        setTemplates(data ?? [])
      } finally {
        setLoading(false)
      }
    }
    void load()
  }, [property.id])

  function openNew() {
    setFormTitle('')
    setFormSeason(activeSeason)
    setFormCategory('maintenance')
    setFormPriority('normal')
    setFormDescription('')
    setShowForm(true)
  }

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    if (!formTitle.trim()) return
    setSaving(true)
    try {
      const supabase = createClient()
      const payload = {
        property_id: property.id,
        season: formSeason,
        title: formTitle.trim(),
        category: formCategory,
        priority: formPriority,
        description: formDescription.trim() || null,
        created_by: userId,
      }
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('seasonal_task_templates')
        .insert(payload)
        .select()
        .single()
      if (error) throw error
      setTemplates((prev) => [data as SeasonalTemplate, ...prev])
      toast({ title: 'Template added' })
      setShowForm(false)
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete(t: SeasonalTemplate) {
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
      await (supabase as any).from('seasonal_task_templates').delete().eq('id', t.id)
      setTemplates((prev) => prev.filter((x) => x.id !== t.id))
      toast({ title: 'Template deleted' })
    } finally {
      setDeletingId(null)
    }
  }

  async function handleGenerateTasks() {
    const seasonTemplates = templates.filter((t) => t.season === currentSeason)
    if (seasonTemplates.length === 0) {
      toast({ title: 'No templates', description: `Add templates for ${SEASON_CONFIG[currentSeason].label} first`, variant: 'destructive' })
      return
    }
    setGenerating(true)
    try {
      const supabase = createClient()
      const dueDate = getSeasonEndDate(currentSeason)

      // Check existing tasks for this season to avoid duplicates
      const seasonStart = (() => {
        const year = new Date().getFullYear()
        const starts: Record<Season, string> = {
          spring: `${year}-03-01`,
          summer: `${year}-06-01`,
          autumn: `${year}-09-01`,
          winter: `${year}-12-01`,
        }
        return starts[currentSeason]
      })()

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: existingTasks } = await (supabase as any)
        .from('maintenance_tasks')
        .select('title')
        .eq('property_id', property.id)
        .gte('created_at', seasonStart)

      const existingTitles = new Set<string>(
        (existingTasks ?? []).map((t: { title: string }) => t.title.toLowerCase())
      )

      const toCreate = seasonTemplates.filter(
        (t) => !existingTitles.has(t.title.toLowerCase())
      )

      if (toCreate.length === 0) {
        toast({ title: 'Already generated', description: 'All tasks for this season have already been created' })
        setGenerating(false)
        return
      }

      const inserts = toCreate.map((t) => ({
        property_id: property.id,
        title: t.title,
        description: t.description,
        category: t.category,
        priority: t.priority ?? 'normal',
        status: 'todo',
        due_date: dueDate,
        created_by: userId,
      }))

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { error } = await (supabase as any)
        .from('maintenance_tasks')
        .insert(inserts)

      if (error) throw error

      toast({
        title: `${toCreate.length} task${toCreate.length === 1 ? '' : 's'} created for ${SEASON_CONFIG[currentSeason].label}`,
      })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setGenerating(false)
    }
  }

  const activeTemplates = templates.filter((t) => t.season === activeSeason)
  const cfg = SEASON_CONFIG[activeSeason]
  const Icon = cfg.Icon

  return (
    <>
      <PageHeader
        title="Seasonal Planner"
        description={property.name}
        backHref="/maintenance"
        action={{ label: 'Add Template', href: '#', onClick: openNew }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Season tabs */}
        <div className="flex gap-1 rounded-xl border border-border/50 p-1 bg-muted/20">
          {SEASONS.map((s) => {
            const c = SEASON_CONFIG[s]
            const SIcon = c.Icon
            const isCurrent = s === currentSeason
            const isActive = s === activeSeason
            return (
              <button
                key={s}
                onClick={() => setActiveSeason(s)}
                className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg px-2 py-2 text-xs font-medium transition-colors ${
                  isActive
                    ? 'bg-background shadow-sm text-foreground'
                    : 'text-muted-foreground hover:text-foreground'
                }`}
              >
                <SIcon className="h-3.5 w-3.5" style={{ color: isActive ? c.color : undefined }} />
                <span className="hidden sm:inline">{c.label}</span>
                {isCurrent && (
                  <span className="inline-flex h-1.5 w-1.5 rounded-full" style={{ background: c.color }} />
                )}
              </button>
            )
          })}
        </div>

        {/* Season header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div
              className="flex h-9 w-9 items-center justify-center rounded-xl"
              style={{ background: `${cfg.color}20` }}
            >
              <Icon className="h-5 w-5" style={{ color: cfg.color }} />
            </div>
            <div>
              <p className="font-semibold text-sm">{cfg.label}</p>
              <p className="text-xs text-muted-foreground">{cfg.months}</p>
            </div>
          </div>
          {activeSeason === currentSeason && (
            <Button
              size="sm"
              variant="secondary"
              onClick={handleGenerateTasks}
              disabled={generating}
            >
              {generating
                ? <><Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />Generating…</>
                : <><Zap className="h-3.5 w-3.5 mr-1" />Generate Tasks</>
              }
            </Button>
          )}
        </div>

        {/* Templates */}
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
          </div>
        ) : activeTemplates.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
            <Icon className="h-10 w-10 opacity-30" />
            <p className="text-sm">No templates for {cfg.label}</p>
            <Button size="sm" onClick={openNew}><Plus className="h-4 w-4 mr-1" />Add Template</Button>
          </div>
        ) : (
          <div className="space-y-2">
            {activeTemplates.map((t) => {
              const priorityColor = t.priority ? (PRIORITY_COLORS[t.priority] ?? PRIORITY_COLORS.normal) : PRIORITY_COLORS.normal
              return (
                <Card key={t.id} className="p-4 flex items-start justify-between gap-3">
                  <div className="flex items-start gap-2 min-w-0">
                    <div
                      className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg"
                      style={{ background: `${cfg.color}20`, color: cfg.color }}
                    >
                      <Icon className="h-4 w-4" />
                    </div>
                    <div className="min-w-0">
                      <p className="font-semibold text-sm truncate">{t.title}</p>
                      {t.description && (
                        <p className="text-xs text-muted-foreground mt-0.5 line-clamp-2">{t.description}</p>
                      )}
                      <div className="flex flex-wrap gap-1.5 mt-1.5">
                        {t.category && (
                          <Badge variant="neutral" size="xs" className="capitalize">{t.category}</Badge>
                        )}
                        {t.priority && (
                          <Badge
                            variant="neutral"
                            size="xs"
                            className="capitalize"
                            style={{ color: priorityColor, borderColor: `${priorityColor}44`, background: `${priorityColor}18` }}
                          >
                            {t.priority}
                          </Badge>
                        )}
                      </div>
                    </div>
                  </div>
                  <button
                    onClick={() => handleDelete(t)}
                    disabled={deletingId === t.id}
                    className="p-1.5 rounded-lg hover:bg-destructive/10 transition-colors text-muted-foreground hover:text-destructive shrink-0"
                  >
                    {deletingId === t.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />}
                  </button>
                </Card>
              )
            })}
          </div>
        )}
      </div>

      {/* Form modal */}
      {showForm && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-lg p-5 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">New Seasonal Template</h2>
              <button onClick={() => setShowForm(false)} className="text-muted-foreground hover:text-foreground">
                <X className="h-4 w-4" />
              </button>
            </div>
            <form onSubmit={handleSave} className="space-y-3">
              <Input
                placeholder="Title *"
                value={formTitle}
                onChange={(e) => setFormTitle(e.target.value)}
                required
              />
              <div>
                <label className="text-xs text-muted-foreground mb-1 block">Season</label>
                <select
                  value={formSeason}
                  onChange={(e) => setFormSeason(e.target.value as Season)}
                  className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                >
                  {SEASONS.map((s) => (
                    <option key={s} value={s}>{SEASON_CONFIG[s].label}</option>
                  ))}
                </select>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs text-muted-foreground mb-1 block">Category</label>
                  <select
                    value={formCategory}
                    onChange={(e) => setFormCategory(e.target.value)}
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
                    value={formPriority}
                    onChange={(e) => setFormPriority(e.target.value)}
                    className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                  >
                    {PRIORITIES.map((p) => (
                      <option key={p} value={p}>{p.charAt(0).toUpperCase() + p.slice(1)}</option>
                    ))}
                  </select>
                </div>
              </div>
              <textarea
                placeholder="Description (optional)"
                value={formDescription}
                onChange={(e) => setFormDescription(e.target.value)}
                rows={2}
                className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <div className="flex justify-end gap-2">
                <Button type="button" variant="ghost" size="sm" onClick={() => setShowForm(false)}>Cancel</Button>
                <Button type="submit" size="sm" disabled={saving}>
                  {saving && <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />}
                  Add template
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}
