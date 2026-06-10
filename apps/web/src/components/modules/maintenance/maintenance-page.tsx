'use client'

import * as React from 'react'
import Link from 'next/link'
import { Wrench, Plus, AlertTriangle, Clock, CheckCircle2, Circle, ChevronRight } from 'lucide-react'
import type { Property, MaintenanceTask, TaskStatus, TaskPriority } from '@/lib/supabase/types'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { formatRelativeTime } from '@/lib/utils'

interface MaintenancePageProps {
  property: Property
  tasks: MaintenanceTask[]
}

const STATUS_CONFIG: Record<TaskStatus, { label: string; icon: React.ComponentType<{ className?: string }> }> = {
  pending: { label: 'Pending', icon: Circle },
  in_progress: { label: 'In Progress', icon: Clock },
  completed: { label: 'Completed', icon: CheckCircle2 },
  cancelled: { label: 'Cancelled', icon: Circle },
  overdue: { label: 'Overdue', icon: AlertTriangle },
}

const PRIORITY_VARIANTS: Record<TaskPriority, 'critical' | 'danger' | 'warning' | 'neutral'> = {
  critical: 'critical',
  high: 'danger',
  medium: 'warning',
  low: 'neutral',
}

const STATUS_TABS: { id: TaskStatus | 'all'; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'pending', label: 'Pending' },
  { id: 'in_progress', label: 'Active' },
  { id: 'overdue', label: 'Overdue' },
  { id: 'completed', label: 'Done' },
  { id: 'cancelled', label: 'Cancelled' },
]

const PRIORITY_FILTERS: { id: TaskPriority | 'all'; label: string }[] = [
  { id: 'all', label: 'All priorities' },
  { id: 'critical', label: 'Critical' },
  { id: 'high', label: 'High' },
  { id: 'medium', label: 'Medium' },
  { id: 'low', label: 'Low' },
]

export function MaintenancePage({ property, tasks }: MaintenancePageProps) {
  const [activeTab, setActiveTab] = React.useState<TaskStatus | 'all'>('all')
  const [priorityFilter, setPriorityFilter] = React.useState<TaskPriority | 'all'>('all')

  const filtered = tasks
    .filter((t) => activeTab === 'all' || t.status === activeTab)
    .filter((t) => priorityFilter === 'all' || t.priority === priorityFilter)

  const overdueCount = tasks.filter((t) => t.status === 'overdue').length
  const pendingCount = tasks.filter((t) => t.status === 'pending').length
  const completedCount = tasks.filter((t) => t.status === 'completed').length

  return (
    <>
      <PageHeader
        title="Maintenance"
        description={property.name}
        action={{ label: 'New Task', href: '/maintenance/new' }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Stats */}
        <div className="grid grid-cols-3 gap-3">
          <StatCard label="Overdue" value={overdueCount} color="hsl(0, 68%, 52%)" alert={overdueCount > 0} />
          <StatCard label="Pending" value={pendingCount} color="hsl(45, 75%, 52%)" />
          <StatCard label="Done (30d)" value={completedCount} color="hsl(152, 62%, 48%)" />
        </div>

        {/* Status tab filter */}
        <div className="flex gap-2 overflow-x-auto scrollbar-hide">
          {STATUS_TABS.map(({ id, label }) => (
            <button
              key={id}
              type="button"
              onClick={() => setActiveTab(id)}
              className={`shrink-0 rounded-full px-3 py-1.5 text-xs font-medium transition-colors ${
                activeTab === id
                  ? 'bg-primary text-white'
                  : 'glass-light text-muted-foreground hover:text-foreground'
              }`}
            >
              {label}
            </button>
          ))}
        </div>

        {/* Priority filter */}
        <div className="flex gap-2 overflow-x-auto scrollbar-hide">
          {PRIORITY_FILTERS.map(({ id, label }) => (
            <button
              key={id}
              type="button"
              onClick={() => setPriorityFilter(id)}
              className={`shrink-0 rounded-full px-3 py-1.5 text-xs font-medium transition-colors ${
                priorityFilter === id
                  ? 'bg-foreground/10 text-foreground ring-1 ring-foreground/20'
                  : 'glass-light text-muted-foreground hover:text-foreground'
              }`}
            >
              {label}
            </button>
          ))}
        </div>

        {/* Task list */}
        {filtered.length === 0 ? (
          <EmptyState status={activeTab} />
        ) : (
          <div className="flex flex-col gap-2">
            {filtered.map((task) => (
              <TaskCard key={task.id} task={task} />
            ))}
          </div>
        )}
      </div>
    </>
  )
}

function StatCard({
  label,
  value,
  color,
  alert,
}: {
  label: string
  value: number
  color: string
  alert?: boolean
}) {
  return (
    <Card variant="default" padding="sm">
      <p className="text-xl font-bold" style={{ color: alert && value > 0 ? 'hsl(0, 68%, 52%)' : color }}>
        {value}
      </p>
      <p className="text-xs text-muted-foreground mt-0.5">{label}</p>
    </Card>
  )
}

function TaskCard({ task }: { task: MaintenanceTask }) {
  const StatusIcon = STATUS_CONFIG[task.status].icon
  const isOverdue = task.status === 'overdue'
  const isCompleted = task.status === 'completed'
  const isCancelled = task.status === 'cancelled'

  return (
    <Link href={`/maintenance/${task.id}`}>
      <Card variant="default" hover padding="md" className="group">
        <div className="flex items-start gap-3">
          <StatusIcon
            className={`h-5 w-5 shrink-0 mt-0.5 ${
              isOverdue
                ? 'text-destructive'
                : isCompleted
                  ? 'text-success'
                  : isCancelled
                    ? 'text-muted-foreground/50'
                    : 'text-muted-foreground'
            }`}
          />
          <div className="flex-1 min-w-0">
            <div className="flex items-start justify-between gap-2">
              <p className={`text-sm font-medium truncate ${isCompleted || isCancelled ? 'line-through text-muted-foreground' : 'text-foreground'}`}>
                {task.title}
              </p>
              <div className="flex shrink-0 items-center gap-1.5">
                <Badge variant={PRIORITY_VARIANTS[task.priority]} size="xs">
                  {task.priority}
                </Badge>
                <ChevronRight className="h-3.5 w-3.5 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
              </div>
            </div>
            {task.description && (
              <p className="text-xs text-muted-foreground mt-0.5 line-clamp-1">{task.description}</p>
            )}
            <div className="mt-1.5 flex flex-wrap items-center gap-2">
              <Badge variant="neutral" size="xs" className="capitalize">
                {task.category}
              </Badge>
              {task.due_date && (
                <span className={`text-[10px] ${isOverdue ? 'text-destructive' : 'text-muted-foreground'}`}>
                  {isOverdue ? 'Was due' : 'Due'} {formatRelativeTime(task.due_date)}
                </span>
              )}
              {task.estimated_cost && (
                <span className="text-[10px] text-muted-foreground">
                  ~€{task.estimated_cost}
                </span>
              )}
              {task.assigned_to_member_id && (
                <span className="text-[10px] text-muted-foreground flex items-center gap-0.5">
                  <span className="inline-block h-1.5 w-1.5 rounded-full bg-primary/60" />
                  Assigned
                </span>
              )}
            </div>
          </div>
        </div>
      </Card>
    </Link>
  )
}

function EmptyState({ status }: { status: TaskStatus | 'all' }) {
  return (
    <div className="flex flex-col items-center gap-3 py-16 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-2xl glass-standard">
        <Wrench className="h-7 w-7 text-muted-foreground" />
      </div>
      <p className="font-semibold text-foreground">
        {status === 'all' ? 'No tasks yet' : `No ${STATUS_CONFIG[status as TaskStatus]?.label.toLowerCase() ?? ''} tasks`}
      </p>
      <p className="text-sm text-muted-foreground max-w-[200px]">
        {status === 'all'
          ? 'Track repairs, inspections, and home maintenance'
          : 'All clear in this category'}
      </p>
    </div>
  )
}
