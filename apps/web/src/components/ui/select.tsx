import * as React from 'react'
import { ChevronDown } from 'lucide-react'
import { cn } from '@/lib/utils'

export interface SelectProps extends React.SelectHTMLAttributes<HTMLSelectElement> {
  label?: string
  hint?: string
  error?: string
  placeholder?: string
  inputSize?: 'sm' | 'md' | 'lg'
}

const Select = React.forwardRef<HTMLSelectElement, SelectProps>(
  ({ className, label, hint, error, placeholder, inputSize = 'md', id, children, ...props }, ref) => {
    const inputId = id ?? React.useId()

    const sizeClasses = {
      sm: 'h-9 text-sm px-3 pr-9',
      md: 'h-11 text-sm px-4 pr-10',
      lg: 'h-13 text-base px-4 pr-10',
    }

    return (
      <div className="flex w-full flex-col gap-1.5">
        {label && (
          <label htmlFor={inputId} className="block text-xs text-muted-foreground">
            {label}
          </label>
        )}
        <div className="relative flex items-center">
          <select
            id={inputId}
            ref={ref}
            className={cn(
              'w-full appearance-none rounded-xl border border-border glass-light',
              'text-foreground bg-transparent',
              'outline-none transition-all duration-normal',
              'focus:ring-2 focus:ring-primary/60',
              'disabled:opacity-40 disabled:cursor-not-allowed',
              'aria-invalid:border-destructive',
              sizeClasses[inputSize],
              className
            )}
            aria-invalid={error ? 'true' : undefined}
            aria-describedby={error ? `${inputId}-error` : hint ? `${inputId}-hint` : undefined}
            {...props}
          >
            {placeholder && <option value="">{placeholder}</option>}
            {children}
          </select>
          <ChevronDown className="pointer-events-none absolute right-3 h-4 w-4 text-muted-foreground" />
        </div>
        {error && (
          <p id={`${inputId}-error`} className="flex items-center gap-1 text-xs text-destructive" role="alert">
            <span className="inline-block h-3 w-3 rounded-full bg-destructive/20 text-center leading-none text-[9px]">!</span>
            {error}
          </p>
        )}
        {hint && !error && (
          <p id={`${inputId}-hint`} className="text-xs text-muted-foreground">{hint}</p>
        )}
      </div>
    )
  }
)
Select.displayName = 'Select'

export { Select }
