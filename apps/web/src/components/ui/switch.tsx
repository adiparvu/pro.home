'use client'

import * as React from 'react'
import * as SwitchPrimitive from '@radix-ui/react-switch'
import { cn } from '@/lib/utils'

const Switch = React.forwardRef<
  React.ElementRef<typeof SwitchPrimitive.Root>,
  React.ComponentPropsWithoutRef<typeof SwitchPrimitive.Root>
>(({ className, ...props }, ref) => (
  <SwitchPrimitive.Root
    className={cn(
      'peer inline-flex h-[22px] w-[36px] shrink-0 cursor-pointer items-center',
      'rounded-full border-2 border-transparent',
      'transition-colors duration-normal',
      'focus-visible:outline-none focus-visible:ring-2',
      'focus-visible:ring-[color:var(--color-focus-ring)] focus-visible:ring-offset-2',
      'disabled:cursor-not-allowed disabled:opacity-40',
      'data-[state=checked]:bg-[hsl(152,62%,38%)]',
      'data-[state=unchecked]:bg-[var(--glass-border)] data-[state=unchecked]:bg-opacity-100',
      'data-[state=unchecked]:bg-[rgba(255,255,255,0.18)]',
      className
    )}
    {...props}
    ref={ref}
  >
    <SwitchPrimitive.Thumb
      className={cn(
        'pointer-events-none block h-[18px] w-[18px] rounded-full bg-white shadow-2',
        'ring-0 transition-transform duration-normal',
        'data-[state=checked]:translate-x-[14px]',
        'data-[state=unchecked]:translate-x-0'
      )}
    />
  </SwitchPrimitive.Root>
))
Switch.displayName = SwitchPrimitive.Root.displayName

export { Switch }
