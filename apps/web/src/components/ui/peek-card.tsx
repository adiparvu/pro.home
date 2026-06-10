import * as React from 'react'
import { StatusChip } from '@/components/ui/chip'

export interface PeekMetaRow {
  icon?: React.ComponentType<{ className?: string }>
  label: string
}

interface PeekCardProps {
  icon: React.ComponentType<{ className?: string; style?: React.CSSProperties }>
  iconColor: string
  title: string
  subtitle?: string | null
  status?: string
  meta?: PeekMetaRow[]
}

/**
 * Peek & Pop preview card — rendered by ContextMenu's `preview` slot.
 * One layout for every module so long-press previews look identical
 * across tasks, plants, inventory items and documents.
 */
export function PeekCard({ icon: Icon, iconColor, title, subtitle, status, meta = [] }: PeekCardProps) {
  return (
    <div className="overflow-hidden rounded-2xl glass-opaque shadow-4 p-4">
      <div className="flex items-start gap-3">
        <div
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl"
          style={{ background: `color-mix(in srgb, ${iconColor} 15%, transparent)` }}
        >
          <Icon className="h-5 w-5" style={{ color: iconColor }} />
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-2">
            <p className="text-sm font-semibold leading-snug text-foreground">{title}</p>
            {status && <StatusChip status={status} size="xs" className="shrink-0" />}
          </div>
          {subtitle && (
            <p className="mt-0.5 truncate text-xs text-muted-foreground">{subtitle}</p>
          )}
        </div>
      </div>
      {meta.length > 0 && (
        <div className="mt-3 flex flex-col gap-1.5 border-t border-border/40 pt-3">
          {meta.map((row) => {
            const RowIcon = row.icon
            return (
              <div key={row.label} className="flex items-center gap-1.5 text-xs text-muted-foreground">
                {RowIcon && <RowIcon className="h-3.5 w-3.5 shrink-0" />}
                <span className="truncate">{row.label}</span>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
