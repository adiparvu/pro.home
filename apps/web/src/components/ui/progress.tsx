import * as React from 'react'
import { cn } from '@/lib/utils'

interface ProgressProps extends React.HTMLAttributes<HTMLDivElement> {
  value?: number
  max?: number
  color?: string
  size?: 'xs' | 'sm' | 'md'
  showLabel?: boolean
}

function Progress({ value = 0, max = 100, color, size = 'sm', showLabel, className, ...props }: ProgressProps) {
  const pct = Math.min(100, Math.max(0, (value / max) * 100))
  const defaultColor = pct >= 80 ? 'hsl(0,68%,52%)' : pct >= 60 ? 'hsl(45,75%,42%)' : 'hsl(210,75%,42%)'
  const trackColor = color ?? defaultColor

  const heightCls = {
    xs: 'h-1',
    sm: 'h-1.5',
    md: 'h-2.5',
  }[size]

  return (
    <div className={cn('flex flex-col gap-1', className)} {...props}>
      {showLabel && (
        <div className="flex items-center justify-between">
          <span className="text-xs text-muted-foreground">{Math.round(pct)}%</span>
        </div>
      )}
      <div
        role="progressbar"
        aria-valuenow={value}
        aria-valuemin={0}
        aria-valuemax={max}
        className={cn('w-full overflow-hidden rounded-full glass-light', heightCls)}
      >
        <div
          className="h-full rounded-full transition-all duration-slow"
          style={{ width: `${pct}%`, background: trackColor }}
        />
      </div>
    </div>
  )
}

export { Progress }
