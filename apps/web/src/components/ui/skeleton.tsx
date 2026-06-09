import { cn } from '@/lib/utils'

interface SkeletonProps extends React.HTMLAttributes<HTMLDivElement> {
  variant?: 'text' | 'heading' | 'card' | 'avatar' | 'icon' | 'default'
}

function Skeleton({ className, variant = 'default', ...props }: SkeletonProps) {
  return (
    <div
      className={cn(
        'skeleton',
        variant === 'text' && 'h-3.5 rounded-full',
        variant === 'heading' && 'h-5 rounded-full',
        variant === 'card' && 'rounded-2xl',
        variant === 'avatar' && 'rounded-full',
        variant === 'icon' && 'rounded-sm',
        className
      )}
      aria-hidden="true"
      {...props}
    />
  )
}

export { Skeleton }
