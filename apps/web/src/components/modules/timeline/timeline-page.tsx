'use client'

import { useState } from 'react'
import { Wrench, Banknote, FileText, Archive, TrendingUp, FileSignature, Clock } from 'lucide-react'
import type { Property } from '@/lib/supabase/types'
import { PageHeader } from '@/components/layout/page-header'

interface TimelineEvent {
  id: string
  source: 'maintenance' | 'finance' | 'document' | 'inventory' | 'valuation' | 'lease'
  title: string
  subtitle: string | null
  date: string
  meta?: string | null
}

type FilterSource = 'all' | TimelineEvent['source']

interface FilterChip {
  value: FilterSource
  label: string
}

const FILTER_CHIPS: FilterChip[] = [
  { value: 'all', label: 'All' },
  { value: 'maintenance', label: 'Maintenance' },
  { value: 'finance', label: 'Finance' },
  { value: 'document', label: 'Documents' },
  { value: 'inventory', label: 'Inventory' },
  { value: 'valuation', label: 'Valuations' },
  { value: 'lease', label: 'Leases' },
]

const SOURCE_CONFIG: Record<
  TimelineEvent['source'],
  { icon: React.ElementType; color: string }
> = {
  maintenance: { icon: Wrench, color: 'hsl(22, 68%, 41%)' },
  finance: { icon: Banknote, color: 'hsl(45, 75%, 42%)' },
  document: { icon: FileText, color: 'hsl(220, 52%, 46%)' },
  inventory: { icon: Archive, color: 'hsl(185, 62%, 38%)' },
  valuation: { icon: TrendingUp, color: 'hsl(152, 62%, 38%)' },
  lease: { icon: FileSignature, color: 'hsl(210, 75%, 42%)' },
}

function getGroup(dateStr: string): string {
  const d = new Date(dateStr)
  const now = new Date()
  const diffDays = (now.getTime() - d.getTime()) / 86400000
  if (diffDays < 1) return 'Today'
  if (diffDays < 7) return 'This week'
  if (diffDays < 30) return 'This month'
  return d.toLocaleDateString('en', { month: 'short', year: 'numeric' })
}

function formatRelativeDate(dateStr: string): string {
  const d = new Date(dateStr)
  const now = new Date()
  const diffMs = now.getTime() - d.getTime()
  const diffMins = Math.floor(diffMs / 60000)
  const diffHours = Math.floor(diffMs / 3600000)
  const diffDays = Math.floor(diffMs / 86400000)

  if (diffMins < 1) return 'just now'
  if (diffMins < 60) return `${diffMins}m ago`
  if (diffHours < 24) return `${diffHours}h ago`
  if (diffDays < 7) return `${diffDays}d ago`
  return d.toLocaleDateString('en', { month: 'short', day: 'numeric', year: diffDays > 365 ? 'numeric' : undefined })
}

export function TimelinePage({ property, events }: { property: Property; events: TimelineEvent[] }) {
  const [filterSource, setFilterSource] = useState<FilterSource>('all')

  const filtered = filterSource === 'all' ? events : events.filter((e) => e.source === filterSource)

  // Group events by date group
  const groups: { label: string; events: TimelineEvent[] }[] = []
  for (const event of filtered) {
    const label = getGroup(event.date)
    const existing = groups.find((g) => g.label === label)
    if (existing) {
      existing.events.push(event)
    } else {
      groups.push({ label, events: [event] })
    }
  }

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <PageHeader title="Timeline" description={property.name} />

      {/* Filter chips */}
      <div className="px-4 md:px-6 pb-2 pt-1">
        <div className="flex gap-2 overflow-x-auto scrollbar-none pb-1">
          {FILTER_CHIPS.map((chip) => (
            <button
              key={chip.value}
              type="button"
              onClick={() => setFilterSource(chip.value)}
              className={[
                'shrink-0 rounded-full px-3.5 py-1.5 text-[13px] font-medium transition-colors focus-ring',
                filterSource === chip.value
                  ? 'bg-primary text-white'
                  : 'glass-light text-muted-foreground hover:text-foreground',
              ].join(' ')}
            >
              {chip.label}
            </button>
          ))}
        </div>
      </div>

      {/* Timeline content */}
      <div className="px-4 md:px-6 py-4">
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center gap-3 py-20 text-muted-foreground">
            <Clock className="h-10 w-10 opacity-40" />
            <p className="text-sm">No activity yet</p>
          </div>
        ) : (
          <div className="flex flex-col gap-8">
            {groups.map((group) => (
              <div key={group.label}>
                {/* Group header */}
                <p className="mb-3 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  {group.label}
                </p>

                {/* Events for this group */}
                <div className="relative">
                  {/* Vertical line */}
                  <div className="absolute left-4 top-0 bottom-0 border-l-2 border-border" />

                  <div className="flex flex-col gap-0">
                    {group.events.map((event) => {
                      const { icon: Icon, color } = SOURCE_CONFIG[event.source]
                      return (
                        <div key={event.id} className="relative flex gap-4 pb-5 last:pb-0">
                          {/* Dot */}
                          <div
                            className="relative z-10 mt-1 flex h-8 w-8 shrink-0 items-center justify-center rounded-full border-2 border-background"
                            style={{ backgroundColor: `${color}22` }}
                          >
                            <Icon className="h-3.5 w-3.5" style={{ color }} />
                          </div>

                          {/* Content */}
                          <div className="flex flex-1 items-start justify-between gap-2 min-w-0 pt-0.5">
                            <div className="min-w-0">
                              <p className="truncate text-sm font-medium text-foreground leading-snug">
                                {event.title}
                              </p>
                              {event.subtitle && (
                                <p className="mt-0.5 truncate text-xs text-muted-foreground">
                                  {event.subtitle}
                                </p>
                              )}
                            </div>
                            <p className="shrink-0 text-[11px] text-muted-foreground whitespace-nowrap pt-0.5">
                              {formatRelativeDate(event.date)}
                            </p>
                          </div>
                        </div>
                      )
                    })}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
