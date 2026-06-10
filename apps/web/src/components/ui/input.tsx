import * as React from 'react'
import { cn } from '@/lib/utils'

export interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string
  hint?: string
  error?: string
  leftElement?: React.ReactNode
  rightElement?: React.ReactNode
  inputSize?: 'sm' | 'md' | 'lg'
}

const Input = React.forwardRef<HTMLInputElement, InputProps>(
  (
    {
      className,
      type,
      label,
      hint,
      error,
      leftElement,
      rightElement,
      inputSize = 'md',
      id,
      ...props
    },
    ref
  ) => {
    const inputId = id ?? React.useId()

    const sizeClasses = {
      sm: 'h-9 text-sm px-3',
      md: 'h-11 text-base px-4',
      lg: 'h-13 text-md px-4',
    }

    return (
      <div className="flex w-full flex-col gap-1.5">
        {label && (
          <label
            htmlFor={inputId}
            className="block text-sm font-medium text-[var(--text-secondary)]"
          >
            {label}
          </label>
        )}

        <div className="relative flex items-center">
          {leftElement && (
            <span className="absolute left-3 flex items-center text-muted-foreground">
              {leftElement}
            </span>
          )}

          <input
            id={inputId}
            type={type}
            ref={ref}
            className={cn(
              'w-full',
              'glass-light',
              'text-foreground',
              'placeholder:text-muted-foreground/60',
              'rounded-md',
              'outline-none',
              'transition-all duration-normal',
              'focus:border-[color:var(--color-focus-ring)]',
              'focus:shadow-[0_0_0_3px_rgba(46,143,236,0.15)]',
              'focus:border-2',
              'aria-invalid:border-destructive',
              'aria-invalid:focus:shadow-[0_0_0_3px_rgba(180,32,32,0.15)]',
              'disabled:opacity-40 disabled:cursor-not-allowed',
              sizeClasses[inputSize],
              leftElement && 'pl-10',
              rightElement && 'pr-10',
              className
            )}
            aria-invalid={error ? 'true' : undefined}
            aria-describedby={
              error ? `${inputId}-error` : hint ? `${inputId}-hint` : undefined
            }
            {...props}
          />

          {rightElement && (
            <span className="absolute right-3 flex items-center text-muted-foreground">
              {rightElement}
            </span>
          )}
        </div>

        {error && (
          <p
            id={`${inputId}-error`}
            className="flex items-center gap-1.5 text-xs text-destructive"
            role="alert"
          >
            <span className="inline-block h-3 w-3 rounded-full bg-destructive/20 text-center leading-none">!</span>
            {error}
          </p>
        )}

        {hint && !error && (
          <p id={`${inputId}-hint`} className="text-xs text-[var(--text-tertiary)]">
            {hint}
          </p>
        )}
      </div>
    )
  }
)
Input.displayName = 'Input'

export { Input }
