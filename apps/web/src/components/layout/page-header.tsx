'use client'

import Link from 'next/link'
import { ChevronLeft, Plus } from 'lucide-react'
import { Button } from '@/components/ui/button'

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

export function PageHeader({ title, description, backHref, action }: PageHeaderProps) {
  return (
    <header className="glass-opaque sticky top-0 z-20 border-b border-border/50 px-4 py-4 md:px-6">
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-3 min-w-0">
          {backHref && (
            <Link
              href={backHref}
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg glass-light text-muted-foreground hover:text-foreground transition-colors focus-ring"
              aria-label="Go back"
            >
              <ChevronLeft className="h-4 w-4" />
            </Link>
          )}
          <div className="min-w-0">
            <h1 className="truncate text-lg font-bold text-foreground">{title}</h1>
            {description && (
              <p className="truncate text-xs text-muted-foreground">{description}</p>
            )}
          </div>
        </div>

        {action && (
          action.onClick ? (
            <Button size="sm" variant="primary" onClick={action.onClick}>
              <Plus className="h-3.5 w-3.5" />
              {action.label}
            </Button>
          ) : (
            <Button asChild size="sm" variant="primary">
              <Link href={action.href}>
                <Plus className="h-3.5 w-3.5" />
                {action.label}
              </Link>
            </Button>
          )
        )}
      </div>
    </header>
  )
}
