import * as React from 'react'
import { cva, type VariantProps } from 'class-variance-authority'
import { cn } from '@/lib/utils'

const badgeVariants = cva(
  [
    'inline-flex items-center gap-1',
    'rounded-full font-bold tracking-wider uppercase',
    'whitespace-nowrap select-none',
  ],
  {
    variants: {
      variant: {
        default: 'bg-secondary text-secondary-foreground',
        success: 'bg-[hsl(152,65%,14%)] text-[hsl(152,70%,52%)]',
        warning: 'bg-[hsl(38,80%,14%)] text-[hsl(38,90%,60%)]',
        danger: 'bg-[hsl(0,60%,14%)] text-[hsl(0,70%,58%)]',
        info: 'bg-[hsl(210,60%,14%)] text-[hsl(210,80%,62%)]',
        neutral: 'bg-[rgba(255,255,255,0.08)] text-muted-foreground',
        // Module variants
        home: 'bg-[hsl(210,60%,14%)] text-[hsl(210,80%,62%)]',
        family: 'bg-[hsl(340,50%,14%)] text-[hsl(340,70%,62%)]',
        aria: 'bg-[hsl(280,50%,14%)] text-[hsl(280,70%,62%)]',
        security: 'bg-[hsl(0,50%,14%)] text-[hsl(0,70%,58%)]',
        energy: 'bg-[hsl(152,50%,14%)] text-[hsl(152,65%,52%)]',
        maintenance: 'bg-[hsl(22,50%,14%)] text-[hsl(22,70%,58%)]',
        // Health score
        excellent: 'bg-[hsl(152,50%,14%)] text-[hsl(152,70%,42%)]',
        good: 'bg-[hsl(96,50%,14%)] text-[hsl(96,65%,48%)]',
        fair: 'bg-[hsl(45,50%,14%)] text-[hsl(45,80%,52%)]',
        poor: 'bg-[hsl(22,50%,14%)] text-[hsl(22,75%,52%)]',
        critical: 'bg-[hsl(0,50%,14%)] text-[hsl(0,70%,54%)]',
      },
      size: {
        xs: 'h-4 px-1.5 text-[10px]',
        sm: 'h-5 px-2 text-[11px]',
        md: 'h-6 px-2.5 text-xs',
        lg: 'h-7 px-3 text-sm',
      },
    },
    defaultVariants: {
      variant: 'default',
      size: 'sm',
    },
  }
)

export interface BadgeProps
  extends React.HTMLAttributes<HTMLSpanElement>,
    VariantProps<typeof badgeVariants> {
  dot?: boolean
}

function Badge({ className, variant, size, dot, children, ...props }: BadgeProps) {
  return (
    <span className={cn(badgeVariants({ variant, size }), className)} {...props}>
      {dot && (
        <span
          className={cn(
            'h-1.5 w-1.5 rounded-full',
            variant === 'success' && 'bg-[hsl(152,70%,52%)]',
            variant === 'warning' && 'bg-[hsl(38,90%,60%)]',
            variant === 'danger' && 'bg-[hsl(0,70%,58%)]',
            variant === 'info' && 'bg-[hsl(210,80%,62%)]',
            !['success', 'warning', 'danger', 'info'].includes(variant ?? '') &&
              'bg-current'
          )}
        />
      )}
      {children}
    </span>
  )
}

export { Badge, badgeVariants }
