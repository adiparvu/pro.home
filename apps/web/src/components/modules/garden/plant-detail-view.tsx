'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import {
  Droplets, Sun, CalendarDays, MapPin, Tag, StickyNote,
  CheckCircle2, AlertCircle, Clock,
} from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import type { GardenPlant, PlantStatus } from '@/lib/supabase/types'

const STATUS_COLORS: Record<PlantStatus, string> = {
  healthy:         'hsl(152,62%,42%)',
  needs_attention: 'hsl(45,75%,42%)',
  dormant:         'hsl(210,52%,52%)',
  removed:         'hsl(var(--muted-foreground))',
  harvested:       'hsl(88,52%,42%)',
}

const STATUS_LABELS: Record<PlantStatus, string> = {
  healthy:         'Healthy',
  needs_attention: 'Needs attention',
  dormant:         'Dormant',
  removed:         'Removed',
  harvested:       'Harvested',
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

export function PlantDetailView({
  plant: initial,
  zoneName,
}: {
  plant: GardenPlant
  zoneName: string | null
}) {
  const router = useRouter()
  const [plant, setPlant] = React.useState(initial)
  const [isWatering, setIsWatering] = React.useState(false)
  const status = wateringStatus(plant)
  const statusColor = STATUS_COLORS[plant.status]
  const waterColor =
    status === 'overdue' ? 'hsl(0,68%,52%)' :
    status === 'today' ? 'hsl(45,75%,42%)' :
    'hsl(152,62%,42%)'

  async function waterNow() {
    setIsWatering(true)
    const today = new Date().toISOString().split('T')[0]
    const nextDate = plant.watering_frequency_days
      ? new Date(Date.now() + plant.watering_frequency_days * 86400000).toISOString().split('T')[0]
      : null
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('garden_plants').update({
      last_watered: today,
      next_watering: nextDate,
    }).eq('id', plant.id)
    setPlant((p) => ({ ...p, last_watered: today, next_watering: nextDate }))
    setIsWatering(false)
    router.refresh()
  }

  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
      {/* Status + watering hero card */}
      <Card variant="default" padding="lg">
        <div className="flex items-start gap-4">
          <div
            className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl text-3xl"
            style={{ background: `${statusColor}18` }}
          >
            🌿
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <Badge
                variant="neutral"
                size="xs"
                className="capitalize"
                style={{ color: statusColor, borderColor: `${statusColor}44`, background: `${statusColor}14` }}
              >
                {STATUS_LABELS[plant.status]}
              </Badge>
              {plant.species && (
                <span className="text-xs text-muted-foreground italic">{plant.species}</span>
              )}
            </div>
            {zoneName && (
              <div className="mt-1 flex items-center gap-1 text-xs text-muted-foreground">
                <MapPin className="h-3 w-3" />
                {zoneName}
              </div>
            )}
          </div>
        </div>

        {/* Watering section */}
        {plant.watering_frequency_days && (
          <div
            className={cn(
              'mt-4 rounded-xl p-3',
              status === 'overdue' ? 'bg-destructive/10 border border-destructive/20' :
              status === 'today' ? 'bg-[hsl(45,75%,42%)]/10 border border-[hsl(45,75%,42%)]/20' :
              'glass-light'
            )}
          >
            <div className="flex items-center justify-between gap-3">
              <div className="flex items-center gap-2">
                {status === 'overdue' && <AlertCircle className="h-4 w-4 text-destructive" />}
                {status === 'today' && <Clock className="h-4 w-4" style={{ color: 'hsl(45,75%,42%)' }} />}
                {status === 'upcoming' && <Droplets className="h-4 w-4 text-primary" />}
                {status === 'none' && <Droplets className="h-4 w-4 text-muted-foreground" />}
                <div>
                  <p className="text-sm font-medium text-foreground">
                    {status === 'overdue' && 'Watering overdue'}
                    {status === 'today' && 'Water today'}
                    {status === 'upcoming' && plant.next_watering && `Water on ${new Date(plant.next_watering).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}`}
                    {status === 'none' && `Every ${plant.watering_frequency_days} days`}
                  </p>
                  {plant.last_watered && (
                    <p className="text-xs text-muted-foreground">
                      Last watered {new Date(plant.last_watered).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
                    </p>
                  )}
                </div>
              </div>
              {(status === 'overdue' || status === 'today') && (
                <button
                  type="button"
                  onClick={waterNow}
                  disabled={isWatering}
                  className="flex items-center gap-1.5 rounded-xl px-4 py-2 text-sm font-medium text-white transition-opacity disabled:opacity-60"
                  style={{ background: waterColor }}
                >
                  <Droplets className="h-4 w-4" />
                  {isWatering ? 'Watering…' : 'Water now'}
                </button>
              )}
            </div>
          </div>
        )}

        {/* Mark as watered (non-overdue) */}
        {plant.watering_frequency_days && status === 'upcoming' && (
          <button
            type="button"
            onClick={waterNow}
            disabled={isWatering}
            className="mt-3 flex w-full items-center justify-center gap-1.5 rounded-xl glass-light py-2.5 text-sm text-muted-foreground hover:text-foreground transition-colors disabled:opacity-60"
          >
            <CheckCircle2 className="h-4 w-4" />
            {isWatering ? 'Saving…' : 'Mark as watered today'}
          </button>
        )}
      </Card>

      {/* Details */}
      <Card variant="default" padding="md">
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">Details</p>
        <div className="flex flex-col gap-3">
          {plant.sunlight_needs && (
            <div className="flex items-center gap-3">
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg glass-light">
                <Sun className="h-4 w-4 text-muted-foreground" />
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Sunlight</p>
                <p className="text-sm text-foreground capitalize">{plant.sunlight_needs.replace('_', ' ')}</p>
              </div>
            </div>
          )}
          {plant.planted_date && (
            <div className="flex items-center gap-3">
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg glass-light">
                <CalendarDays className="h-4 w-4 text-muted-foreground" />
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Planted</p>
                <p className="text-sm text-foreground">
                  {new Date(plant.planted_date).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })}
                </p>
              </div>
            </div>
          )}
          {plant.fertilizing_frequency_days && (
            <div className="flex items-center gap-3">
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg glass-light">
                <span className="text-sm">🌱</span>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Fertilizing</p>
                <p className="text-sm text-foreground">
                  Every {plant.fertilizing_frequency_days} days
                  {plant.last_fertilized && ` · Last ${new Date(plant.last_fertilized).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}`}
                </p>
              </div>
            </div>
          )}
          {plant.notes && (
            <div className="flex items-start gap-3">
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg glass-light">
                <StickyNote className="h-4 w-4 text-muted-foreground" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-xs text-muted-foreground">Notes</p>
                <p className="text-sm text-foreground whitespace-pre-wrap">{plant.notes}</p>
              </div>
            </div>
          )}
          {plant.tags.length > 0 && (
            <div className="flex items-start gap-3">
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg glass-light">
                <Tag className="h-4 w-4 text-muted-foreground" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-xs text-muted-foreground mb-1.5">Tags</p>
                <div className="flex flex-wrap gap-1">
                  {plant.tags.map((tag) => (
                    <span key={tag} className="rounded-full glass-light px-2.5 py-1 text-xs text-muted-foreground">
                      {tag}
                    </span>
                  ))}
                </div>
              </div>
            </div>
          )}
        </div>
      </Card>
    </div>
  )
}
