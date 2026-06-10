'use client'

import * as React from 'react'
import Link from 'next/link'
import {
  Droplets, Leaf, Sun, Cloud, Sprout, CheckCircle2,
  SkipForward, Plus, CalendarDays, ChevronDown, ChevronUp,
  AlertTriangle, Clock, FlowerIcon,
} from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import type { GardenPlant, GardenTask, GardenZone, GardenTaskType, PlantStatus } from '@/lib/supabase/types'

interface GardenOverviewProps {
  propertyId: string
  plants: GardenPlant[]
  tasks: GardenTask[]
  zones: GardenZone[]
}

const STATUS_COLORS: Record<PlantStatus, string> = {
  healthy:          'hsl(152,62%,42%)',
  needs_attention:  'hsl(45,75%,42%)',
  dormant:          'hsl(210,52%,52%)',
  removed:          'hsl(var(--muted-foreground))',
  harvested:        'hsl(88,52%,42%)',
}

const STATUS_LABELS: Record<PlantStatus, string> = {
  healthy:         'Healthy',
  needs_attention: 'Needs attention',
  dormant:         'Dormant',
  removed:         'Removed',
  harvested:       'Harvested',
}

const TASK_TYPE_LABELS: Record<GardenTaskType, string> = {
  watering:     'Watering',
  fertilizing:  'Fertilizing',
  pruning:      'Pruning',
  harvesting:   'Harvesting',
  planting:     'Planting',
  pest_control: 'Pest control',
  repotting:    'Repotting',
  weeding:      'Weeding',
  general:      'General',
}

const TASK_TYPE_ICONS: Record<GardenTaskType, React.ComponentType<{ className?: string; style?: React.CSSProperties }>> = {
  watering:     Droplets,
  fertilizing:  Sprout,
  pruning:      Leaf,
  harvesting:   FlowerIcon,
  planting:     Leaf,
  pest_control: AlertTriangle,
  repotting:    Sprout,
  weeding:      Leaf,
  general:      CalendarDays,
}

function sunLabel(s: string | null): string {
  if (!s) return ''
  return { full_sun: 'Full sun', partial_shade: 'Partial shade', full_shade: 'Full shade', shade: 'Shade' }[s] ?? s
}

function wateringStatus(plant: GardenPlant): 'overdue' | 'today' | 'upcoming' | 'none' {
  if (!plant.next_watering || !plant.watering_frequency_days) return 'none'
  const today = new Date(); today.setHours(0, 0, 0, 0)
  const next = new Date(plant.next_watering); next.setHours(0, 0, 0, 0)
  const diff = Math.round((next.getTime() - today.getTime()) / 86400000)
  if (diff < 0) return 'overdue'
  if (diff === 0) return 'today'
  return 'upcoming'
}

export function GardenOverview({ propertyId, plants: initialPlants, tasks: initialTasks, zones }: GardenOverviewProps) {
  const [activeTab, setActiveTab] = React.useState<'plants' | 'tasks'>('plants')
  const [plants, setPlants] = React.useState<GardenPlant[]>(initialPlants)
  const [tasks, setTasks] = React.useState<GardenTask[]>(initialTasks)
  const [wateringPlantId, setWateringPlantId] = React.useState<string | null>(null)

  const zoneMap = React.useMemo(() => new Map(zones.map((z) => [z.id, z])), [zones])

  const overduePlants = plants.filter((p) => wateringStatus(p) === 'overdue' && p.status !== 'removed')
  const todayPlants = plants.filter((p) => wateringStatus(p) === 'today' && p.status !== 'removed')
  const activePlants = plants.filter((p) => p.status !== 'removed')
  const pendingTasks = tasks.filter((t) => t.status === 'pending')
  const doneTasks = tasks.filter((t) => t.status === 'done')

  async function waterPlant(plantId: string, freq: number | null) {
    setWateringPlantId(plantId)
    const today = new Date().toISOString().split('T')[0]
    const nextDate = freq
      ? new Date(Date.now() + freq * 86400000).toISOString().split('T')[0]
      : null
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('garden_plants').update({
      last_watered: today,
      next_watering: nextDate,
    }).eq('id', plantId)
    setPlants((prev) => prev.map((p) => p.id === plantId
      ? { ...p, last_watered: today ?? null, next_watering: nextDate ?? null }
      : p
    ))
    setWateringPlantId(null)
  }

  async function completeTask(id: string) {
    const today = new Date().toISOString().split('T')[0]
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('garden_tasks').update({ status: 'done', completed_date: today }).eq('id', id)
    setTasks((prev) => prev.map((t) => t.id === id ? { ...t, status: 'done' as const, completed_date: today ?? null } : t))
  }

  async function skipTask(id: string) {
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('garden_tasks').update({ status: 'skipped' }).eq('id', id)
    setTasks((prev) => prev.filter((t) => t.id !== id))
  }

  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
      {/* Summary chips */}
      <div className="flex gap-2 flex-wrap">
        {overduePlants.length > 0 && (
          <div className="flex items-center gap-1.5 rounded-full border border-destructive/30 bg-destructive/10 px-3 py-1.5 text-xs font-medium text-destructive">
            <Droplets className="h-3.5 w-3.5" />
            {overduePlants.length} plant{overduePlants.length !== 1 ? 's' : ''} need water
          </div>
        )}
        {todayPlants.length > 0 && (
          <div className="flex items-center gap-1.5 rounded-full border border-[hsl(45,75%,42%)]/30 bg-[hsl(45,75%,42%)]/10 px-3 py-1.5 text-xs font-medium" style={{ color: 'hsl(45,75%,42%)' }}>
            <Clock className="h-3.5 w-3.5" />
            {todayPlants.length} due today
          </div>
        )}
        {pendingTasks.length > 0 && (
          <div className="flex items-center gap-1.5 rounded-full glass-light px-3 py-1.5 text-xs font-medium text-muted-foreground">
            <CalendarDays className="h-3.5 w-3.5" />
            {pendingTasks.length} task{pendingTasks.length !== 1 ? 's' : ''} pending
          </div>
        )}
      </div>

      {/* Tab switcher */}
      <div className="flex gap-1 rounded-xl glass-light p-1">
        <button
          type="button"
          onClick={() => setActiveTab('plants')}
          className={cn(
            'flex-1 rounded-lg py-2 text-xs font-medium transition-colors flex items-center justify-center gap-1.5',
            activeTab === 'plants' ? 'bg-primary text-white' : 'text-muted-foreground hover:text-foreground'
          )}
        >
          <Leaf className="h-3.5 w-3.5" />
          Plants
          {activePlants.length > 0 && (
            <span className={cn('rounded-full px-1.5 py-0.5 text-[10px] font-semibold', activeTab === 'plants' ? 'bg-white/20' : 'bg-primary/20 text-primary')}>
              {activePlants.length}
            </span>
          )}
        </button>
        <button
          type="button"
          onClick={() => setActiveTab('tasks')}
          className={cn(
            'flex-1 rounded-lg py-2 text-xs font-medium transition-colors flex items-center justify-center gap-1.5',
            activeTab === 'tasks' ? 'bg-primary text-white' : 'text-muted-foreground hover:text-foreground'
          )}
        >
          <CalendarDays className="h-3.5 w-3.5" />
          Tasks
          {pendingTasks.length > 0 && (
            <span className={cn('rounded-full px-1.5 py-0.5 text-[10px] font-semibold', activeTab === 'tasks' ? 'bg-white/20' : 'bg-primary/20 text-primary')}>
              {pendingTasks.length}
            </span>
          )}
        </button>
      </div>

      {activeTab === 'plants' ? (
        <>
          {activePlants.length === 0 ? (
            <GardenEmptyState
              icon={<Leaf className="h-7 w-7 text-muted-foreground" />}
              title="No plants yet"
              subtitle="Start tracking your garden — add your first plant."
              action={<Link href="/garden/plants/new" className="flex items-center gap-1.5 rounded-lg bg-primary px-3 py-2 text-xs text-white font-medium"><Plus className="h-3.5 w-3.5" />Add plant</Link>}
            />
          ) : (
            <div className="flex flex-col gap-3">
              {activePlants.map((plant) => (
                <PlantCard
                  key={plant.id}
                  plant={plant}
                  zoneName={plant.zone_id ? (zoneMap.get(plant.zone_id)?.name ?? null) : null}
                  watering={wateringStatus(plant)}
                  isWatering={wateringPlantId === plant.id}
                  onWater={() => waterPlant(plant.id, plant.watering_frequency_days)}
                />
              ))}
              <Link
                href="/garden/plants/new"
                className="flex items-center justify-center gap-2 rounded-xl glass-light py-3 text-sm text-muted-foreground hover:text-foreground transition-colors"
              >
                <Plus className="h-4 w-4" />
                Add plant
              </Link>
            </div>
          )}
        </>
      ) : (
        <>
          {pendingTasks.length === 0 && doneTasks.length === 0 ? (
            <GardenEmptyState
              icon={<CalendarDays className="h-7 w-7 text-muted-foreground" />}
              title="No tasks yet"
              subtitle="Schedule watering, pruning, fertilizing and more."
              action={<Link href="/garden/tasks/new" className="flex items-center gap-1.5 rounded-lg bg-primary px-3 py-2 text-xs text-white font-medium"><Plus className="h-3.5 w-3.5" />Add task</Link>}
            />
          ) : (
            <div className="flex flex-col gap-3">
              {pendingTasks.map((task) => (
                <TaskCard
                  key={task.id}
                  task={task}
                  plantName={task.plant_id ? (plants.find((p) => p.id === task.plant_id)?.name ?? null) : null}
                  zoneName={task.zone_id ? (zoneMap.get(task.zone_id)?.name ?? null) : null}
                  onComplete={completeTask}
                  onSkip={skipTask}
                />
              ))}
              {doneTasks.length > 0 && (
                <p className="text-center text-xs text-muted-foreground py-2">
                  {doneTasks.length} completed task{doneTasks.length !== 1 ? 's' : ''} this period
                </p>
              )}
              <Link
                href="/garden/tasks/new"
                className="flex items-center justify-center gap-2 rounded-xl glass-light py-3 text-sm text-muted-foreground hover:text-foreground transition-colors"
              >
                <Plus className="h-4 w-4" />
                Add task
              </Link>
            </div>
          )}
        </>
      )}
    </div>
  )
}

// ─── Plant card ───────────────────────────────────────────────────────────────

function PlantCard({
  plant, zoneName, watering, isWatering, onWater,
}: {
  plant: GardenPlant
  zoneName: string | null
  watering: 'overdue' | 'today' | 'upcoming' | 'none'
  isWatering: boolean
  onWater: () => void
}) {
  const [expanded, setExpanded] = React.useState(false)
  const statusColor = STATUS_COLORS[plant.status]
  const waterColor = watering === 'overdue' ? 'hsl(0,68%,52%)' : watering === 'today' ? 'hsl(45,75%,42%)' : 'hsl(152,62%,42%)'

  return (
    <Card variant="default" padding="md">
      <div className="flex items-start gap-3">
        {/* Icon */}
        <div
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl text-xl"
          style={{ background: `${statusColor}18` }}
        >
          🌿
        </div>

        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <div className="flex items-center gap-1.5 flex-wrap">
                <p className="text-sm font-semibold text-foreground">{plant.name}</p>
                <Badge
                  variant="neutral"
                  size="xs"
                  className="capitalize"
                  style={{ color: statusColor, borderColor: `${statusColor}44`, background: `${statusColor}14` }}
                >
                  {STATUS_LABELS[plant.status]}
                </Badge>
              </div>
              {plant.species && <p className="text-xs text-muted-foreground italic mt-0.5">{plant.species}</p>}
              {zoneName && <p className="text-xs text-muted-foreground">{zoneName}</p>}
            </div>
            <button
              type="button"
              onClick={() => setExpanded((v) => !v)}
              className="flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground hover:text-foreground transition-colors shrink-0"
            >
              {expanded ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
            </button>
          </div>

          {/* Watering row */}
          {plant.watering_frequency_days && (
            <div className="mt-2 flex items-center gap-2">
              <div className="flex items-center gap-1" style={{ color: watering !== 'none' ? waterColor : undefined }}>
                <Droplets className="h-3.5 w-3.5" />
                <span className="text-xs">
                  {watering === 'overdue' && 'Overdue'}
                  {watering === 'today' && 'Water today'}
                  {watering === 'upcoming' && plant.next_watering && `Next ${new Date(plant.next_watering).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}`}
                  {watering === 'none' && `Every ${plant.watering_frequency_days}d`}
                </span>
              </div>
              {(watering === 'overdue' || watering === 'today') && (
                <button
                  type="button"
                  onClick={onWater}
                  disabled={isWatering}
                  className="flex items-center gap-1 rounded-lg px-2.5 py-1 text-xs font-medium text-white transition-colors disabled:opacity-60"
                  style={{ background: waterColor }}
                >
                  <Droplets className="h-3 w-3" />
                  {isWatering ? '…' : 'Water'}
                </button>
              )}
            </div>
          )}

          {/* Expanded details */}
          {expanded && (
            <div className="mt-3 flex flex-col gap-1.5 border-t border-border/40 pt-3">
              {plant.sunlight_needs && (
                <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <Sun className="h-3.5 w-3.5" />
                  {sunLabel(plant.sunlight_needs)}
                </div>
              )}
              {plant.planted_date && (
                <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <CalendarDays className="h-3.5 w-3.5" />
                  Planted {new Date(plant.planted_date).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
                </div>
              )}
              {plant.last_watered && (
                <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <Droplets className="h-3.5 w-3.5" />
                  Last watered {new Date(plant.last_watered).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
                </div>
              )}
              {plant.notes && (
                <p className="text-xs text-muted-foreground">{plant.notes}</p>
              )}
              {plant.tags.length > 0 && (
                <div className="flex flex-wrap gap-1 mt-1">
                  {plant.tags.map((tag) => (
                    <span key={tag} className="rounded-full glass-light px-2 py-0.5 text-[10px] text-muted-foreground">{tag}</span>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </Card>
  )
}

// ─── Task card ────────────────────────────────────────────────────────────────

function TaskCard({
  task, plantName, zoneName, onComplete, onSkip,
}: {
  task: GardenTask
  plantName: string | null
  zoneName: string | null
  onComplete: (id: string) => void
  onSkip: (id: string) => void
}) {
  const Icon = TASK_TYPE_ICONS[task.task_type] ?? CalendarDays
  const isOverdue = task.due_date && new Date(task.due_date) < new Date()
  const color = isOverdue ? 'hsl(0,68%,52%)' : 'hsl(152,62%,42%)'

  return (
    <Card variant="default" padding="md">
      <div className="flex items-start gap-3">
        <div
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl"
          style={{ background: `${color}18` }}
        >
          <Icon className="h-5 w-5" style={{ color }} />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-start gap-2">
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-foreground">{task.title}</p>
              <div className="flex items-center gap-2 flex-wrap mt-0.5">
                <Badge variant="neutral" size="xs">{TASK_TYPE_LABELS[task.task_type]}</Badge>
                {plantName && <span className="text-[10px] text-muted-foreground">{plantName}</span>}
                {zoneName && <span className="text-[10px] text-muted-foreground">{zoneName}</span>}
              </div>
              {task.due_date && (
                <p className="text-xs mt-1" style={{ color: isOverdue ? 'hsl(0,68%,52%)' : undefined }}>
                  {isOverdue ? 'Overdue — ' : ''}
                  {new Date(task.due_date).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
                </p>
              )}
              {task.notes && <p className="text-xs text-muted-foreground mt-0.5">{task.notes}</p>}
            </div>
          </div>
          <div className="mt-3 flex gap-2">
            <button
              type="button"
              onClick={() => onComplete(task.id)}
              className="flex items-center gap-1 rounded-lg bg-[hsl(152,62%,42%)] px-3 py-1.5 text-xs text-white font-medium transition-colors hover:opacity-90"
            >
              <CheckCircle2 className="h-3.5 w-3.5" />
              Done
            </button>
            <button
              type="button"
              onClick={() => onSkip(task.id)}
              className="flex items-center gap-1 rounded-lg glass-light px-3 py-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
            >
              <SkipForward className="h-3.5 w-3.5" />
              Skip
            </button>
          </div>
        </div>
      </div>
    </Card>
  )
}

// ─── Empty state ──────────────────────────────────────────────────────────────

function GardenEmptyState({ icon, title, subtitle, action }: {
  icon: React.ReactNode; title: string; subtitle: string; action?: React.ReactNode
}) {
  return (
    <div className="flex flex-col items-center gap-3 py-16 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-2xl glass-standard">{icon}</div>
      <p className="font-semibold text-foreground">{title}</p>
      <p className="text-sm text-muted-foreground max-w-[220px]">{subtitle}</p>
      {action}
    </div>
  )
}
