import * as React from 'react'
import { cn } from '@/lib/utils'

export type ChipTone = 'success' | 'warning' | 'danger' | 'info' | 'neutral' | 'accent'

/**
 * Centralized status → tone mapping. Every module renders statuses through
 * this map so the same state always looks the same everywhere.
 */
const STATUS_TONES: Record<string, ChipTone> = {
  // Generic workflow
  active: 'success',
  pending: 'warning',
  in_progress: 'info',
  completed: 'success',
  done: 'success',
  cancelled: 'neutral',
  delayed: 'warning',
  urgent: 'danger',
  approved: 'success',
  rejected: 'danger',
  overdue: 'danger',
  skipped: 'neutral',
  draft: 'neutral',
  sent: 'info',
  // Priority
  critical: 'danger',
  high: 'danger',
  medium: 'warning',
  low: 'neutral',
  // Inventory / stock
  in_stock: 'success',
  low_stock: 'warning',
  out_of_stock: 'danger',
  excellent: 'success',
  good: 'success',
  fair: 'warning',
  poor: 'danger',
  broken: 'danger',
  // Garden
  healthy: 'success',
  needs_attention: 'warning',
  dormant: 'info',
  harvested: 'success',
  removed: 'neutral',
  // Documents / membership
  expired: 'danger',
  expiring: 'warning',
  pending_invite: 'warning',
  suspended: 'danger',
  inactive: 'neutral',
  // Security
  armed: 'success',
  disarmed: 'neutral',
  home: 'success',
  away: 'info',
  night: 'info',
  vacation: 'info',
  // Notifications
  unread: 'info',
  read: 'neutral',
}

const TONE_CLASSES: Record<ChipTone, string> = {
  success: 'bg-[hsl(152,65%,14%)] text-[hsl(152,70%,52%)] border-[hsl(152,65%,30%)]/30',
  warning: 'bg-[hsl(38,80%,14%)] text-[hsl(38,90%,60%)] border-[hsl(38,80%,35%)]/30',
  danger: 'bg-[hsl(0,60%,14%)] text-[hsl(0,70%,58%)] border-[hsl(0,60%,35%)]/30',
  info: 'bg-[hsl(210,60%,14%)] text-[hsl(210,80%,62%)] border-[hsl(210,60%,35%)]/30',
  neutral: 'bg-[rgba(255,255,255,0.08)] text-muted-foreground border-white/10',
  accent: 'bg-primary/15 text-primary border-primary/25',
}

const SIZE_CLASSES = {
  xs: 'h-4 px-1.5 text-[10px]',
  sm: 'h-5 px-2 text-[11px]',
  md: 'h-6 px-2.5 text-xs',
} as const

export interface ChipProps extends React.HTMLAttributes<HTMLSpanElement> {
  tone?: ChipTone
  size?: keyof typeof SIZE_CLASSES
  icon?: React.ReactNode
}

/** Generic pill chip with a semantic tone. */
export function Chip({ tone = 'neutral', size = 'sm', icon, className, children, ...props }: ChipProps) {
  return (
    <span
      className={cn(
        'inline-flex select-none items-center gap-1 whitespace-nowrap rounded-full border font-semibold uppercase tracking-wider',
        TONE_CLASSES[tone],
        SIZE_CLASSES[size],
        className
      )}
      {...props}
    >
      {icon}
      {children}
    </span>
  )
}

export interface StatusChipProps extends Omit<ChipProps, 'tone'> {
  /** Domain status value, e.g. "in_progress", "low_stock", "needs_attention" */
  status: string
  /** Override the auto-derived label */
  label?: string
}

/** Status chip — derives tone and label from the centralized status map. */
export function StatusChip({ status, label, ...props }: StatusChipProps) {
  const tone = STATUS_TONES[status] ?? 'neutral'
  return (
    <Chip tone={tone} {...props}>
      {label ?? status.replace(/_/g, ' ')}
    </Chip>
  )
}
