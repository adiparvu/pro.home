'use client'

import Link from 'next/link'
import { ChevronLeft, Plus } from 'lucide-react'
import { useScrollDirection } from '@/hooks/use-scroll-direction'
import { cn } from '@/lib/utils'

interface PageHeaderProps {
  title: string
  description?: string
  backHref?: string
  action?: {
    label: string
    href: string
    onClick?: () => void
  }
}

/**
 * Apple-style large-title header. At rest the title renders large in the
 * content flow with a transparent inline bar; once the page scrolls past the
 * collapse threshold the inline bar gains glass and the title shrinks into
 * it. The collapsed state matches the previous PageHeader appearance, so
 * existing screens keep their look mid-scroll.
 */
export function PageHeader({ title, description, backHref, action }: PageHeaderProps) {
  const { collapsed } = useScrollDirection()

  const actionButton = action && (
    action.onClick ? (
      <button
        type="button"
        onClick={action.onClick}
        className="flex h-9 shrink-0 items-center gap-1 rounded-full bg-primary pl-2.5 pr-3.5 text-sm font-semibold text-white shadow-glow-home transition-opacity hover:opacity-90 active:scale-95 focus-ring"
      >
        <Plus className="h-4 w-4" />
        {action.label}
      </button>
    ) : (
      <Link
        href={action.href}
        className="flex h-9 shrink-0 items-center gap-1 rounded-full bg-primary pl-2.5 pr-3.5 text-sm font-semibold text-white shadow-glow-home transition-opacity hover:opacity-90 active:scale-95 focus-ring"
      >
        <Plus className="h-4 w-4" />
        {action.label}
      </Link>
    )
  )

  return (
    <>
      {/* Inline bar — transparent at rest, glass when collapsed */}
      <header
        className={cn(
          'sticky top-0 z-20 px-4 md:px-6 transition-all duration-normal',
          collapsed
            ? 'glass-standard border-b border-border/50'
            : 'border-b border-transparent'
        )}
      >
        <div className="flex h-14 items-center justify-between gap-3">
          <div className="flex min-w-0 items-center gap-3">
            {backHref && (
              <Link
                href={backHref}
                className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full glass-light text-muted-foreground hover:text-foreground transition-colors focus-ring"
                aria-label="Go back"
              >
                <ChevronLeft className="h-4 w-4" />
              </Link>
            )}
            {/* Collapsed title — fades/slides in once the large title scrolls away */}
            <p
              className={cn(
                'truncate text-[17px] font-semibold text-foreground transition-all duration-normal',
                collapsed ? 'translate-y-0 opacity-100' : 'translate-y-2 opacity-0'
              )}
              aria-hidden="true"
            >
              {title}
            </p>
          </div>
          {actionButton}
        </div>
      </header>

      {/* Large title — lives in the content flow and scrolls away */}
      <div className="px-4 pb-2 pt-1 md:px-6">
        <h1 className="text-[28px] font-bold leading-tight tracking-[-0.02em] text-foreground">
          {title}
        </h1>
        {description && (
          <p className="mt-0.5 truncate text-[13px] text-muted-foreground">{description}</p>
        )}
      </div>
    </>
  )
}
