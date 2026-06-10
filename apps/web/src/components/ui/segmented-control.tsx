'use client'

import * as React from 'react'
import { useSlidingThumb } from '@/hooks/use-sliding-thumb'
import { cn } from '@/lib/utils'

export interface SegmentedOption<T extends string> {
  value: T
  label: string
  icon?: React.ComponentType<{ className?: string }>
  count?: number
}

interface SegmentedControlProps<T extends string> {
  options: SegmentedOption<T>[]
  value: T
  onChange: (value: T) => void
  size?: 'sm' | 'md'
  fullWidth?: boolean
  className?: string
  'aria-label'?: string
}

/**
 * iOS-style segmented control with an animated sliding thumb.
 * Use for view switches and mutually-exclusive filters:
 * All | Active | Completed · Plants | Tasks | Zones · Today | Week | Month
 */
export function SegmentedControl<T extends string>({
  options,
  value,
  onChange,
  size = 'md',
  fullWidth = true,
  className,
  'aria-label': ariaLabel,
}: SegmentedControlProps<T>) {
  const { containerRef, setItemRef, thumb } = useSlidingThumb(value, [options.length])

  return (
    <div
      ref={containerRef}
      role="tablist"
      aria-label={ariaLabel}
      className={cn(
        'relative flex gap-0.5 overflow-x-auto scrollbar-hide rounded-xl glass-light p-1',
        fullWidth ? 'w-full' : 'w-fit',
        className
      )}
    >
      {/* Sliding thumb */}
      {thumb && (
        <div
          className="absolute top-1 bottom-1 rounded-lg glass-standard shadow-2 transition-all duration-normal ease-spring-out"
          style={{ left: thumb.left, width: thumb.width }}
          aria-hidden="true"
        />
      )}

      {options.map((option) => {
        const isActive = option.value === value
        const Icon = option.icon
        return (
          <button
            key={option.value}
            ref={setItemRef(option.value)}
            type="button"
            role="tab"
            aria-selected={isActive}
            onClick={() => onChange(option.value)}
            className={cn(
              'relative z-10 flex shrink-0 items-center justify-center gap-1.5 rounded-lg font-medium transition-colors focus-ring',
              fullWidth && 'flex-1',
              size === 'sm' ? 'px-2.5 py-1 text-xs' : 'px-3 py-1.5 text-xs md:text-sm',
              isActive ? 'text-foreground' : 'text-muted-foreground hover:text-foreground'
            )}
          >
            {Icon && <Icon className="h-3.5 w-3.5" />}
            <span className="whitespace-nowrap">{option.label}</span>
            {option.count !== undefined && option.count > 0 && (
              <span
                className={cn(
                  'rounded-full px-1.5 py-px text-[10px] font-semibold',
                  isActive ? 'bg-primary/20 text-primary' : 'bg-white/10 text-muted-foreground'
                )}
              >
                {option.count}
              </span>
            )}
          </button>
        )
      })}
    </div>
  )
}
