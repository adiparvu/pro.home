import * as React from 'react'
import { Slot } from '@radix-ui/react-slot'
import { cva, type VariantProps } from 'class-variance-authority'
import { cn } from '@/lib/utils'

const buttonVariants = cva(
  [
    'inline-flex items-center justify-center gap-2',
    'font-semibold tracking-[-0.01em] whitespace-nowrap',
    'select-none cursor-pointer',
    'transition-all duration-fast ease-out',
    'focus-ring',
    'active:scale-[0.96]',
    'disabled:opacity-40 disabled:pointer-events-none',
    '[&_svg]:pointer-events-none [&_svg]:shrink-0',
  ],
  {
    variants: {
      variant: {
        primary: [
          'bg-primary text-primary-foreground',
          'shadow-2',
          'hover:brightness-110',
        ],
        secondary: [
          'glass-light',
          'text-foreground',
          'hover:bg-[rgba(255,255,255,0.10)]',
        ],
        ghost: [
          'bg-transparent text-muted-foreground',
          'hover:bg-[var(--color-hover)] hover:text-foreground',
        ],
        destructive: [
          'bg-destructive text-destructive-foreground',
          'shadow-2',
          'hover:brightness-110',
        ],
        glass: [
          'glass-standard',
          'text-foreground',
          'hover:bg-[rgba(255,255,255,0.12)]',
        ],
        outline: [
          'border border-border bg-transparent text-foreground',
          'hover:bg-[var(--color-hover)]',
        ],
        link: [
          'bg-transparent text-primary underline-offset-4 hover:underline',
          'h-auto px-0',
        ],
      },
      size: {
        xs: 'h-7 px-3 text-xs rounded-sm',
        sm: 'h-9 px-4 text-sm rounded-md',
        md: 'h-11 px-5 text-base rounded-md',
        lg: 'h-13 px-6 text-md rounded-md',
        xl: 'h-16 px-8 text-lg rounded-md',
        icon: 'h-11 w-11 rounded-md',
        'icon-sm': 'h-9 w-9 rounded-sm',
        'icon-xs': 'h-7 w-7 rounded-xs',
      },
      fullWidth: {
        true: 'w-full',
      },
    },
    defaultVariants: {
      variant: 'primary',
      size: 'md',
    },
  }
)

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean
  loading?: boolean
  leftIcon?: React.ReactNode
  rightIcon?: React.ReactNode
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  (
    {
      className,
      variant,
      size,
      fullWidth,
      asChild = false,
      loading = false,
      leftIcon,
      rightIcon,
      children,
      disabled,
      ...props
    },
    ref
  ) => {
    const Comp = asChild ? Slot : 'button'

    return (
      <Comp
        className={cn(buttonVariants({ variant, size, fullWidth, className }))}
        ref={ref}
        disabled={disabled ?? loading}
        aria-busy={loading}
        {...props}
      >
        {loading ? (
          <>
            <span className="h-4 w-4 animate-spin-slow rounded-full border-2 border-current border-t-transparent" />
            <span className="sr-only">Loading</span>
          </>
        ) : (
          <>
            {leftIcon && <span className="shrink-0">{leftIcon}</span>}
            {children}
            {rightIcon && <span className="shrink-0">{rightIcon}</span>}
          </>
        )}
      </Comp>
    )
  }
)
Button.displayName = 'Button'

export { Button, buttonVariants }
