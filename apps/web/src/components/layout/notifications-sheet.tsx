'use client'

import * as React from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { Bell, Inbox } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import type { Notification } from '@/lib/supabase/types'
import { BottomSheet } from '@/components/ui/bottom-sheet'
import { Badge } from '@/components/ui/badge'
import { StatusChip } from '@/components/ui/chip'
import { formatRelativeTime } from '@/lib/utils'
import { cn } from '@/lib/utils'

/**
 * Bell trigger + bottom-sheet preview of the latest notifications.
 * Quick glance without leaving the current page; full management lives
 * at /notifications.
 */
export function NotificationsSheet({ count = 0 }: { count?: number }) {
  const router = useRouter()
  const [open, setOpen] = React.useState(false)
  const [notifications, setNotifications] = React.useState<Notification[] | null>(null)

  React.useEffect(() => {
    if (!open) return
    let cancelled = false
    async function load() {
      const supabase = createClient()
      const { data } = await supabase
        .from('notifications')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(8) as { data: Notification[] | null; error: unknown }
      if (!cancelled) setNotifications(data ?? [])
    }
    load()
    return () => { cancelled = true }
  }, [open])

  async function openNotification(n: Notification) {
    setOpen(false)
    if (n.status === 'unread') {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any)
        .from('notifications')
        .update({ status: 'read', read_at: new Date().toISOString() })
        .eq('id', n.id)
    }
    router.push(n.action_url ?? '/notifications')
    router.refresh()
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="relative flex h-9 w-9 items-center justify-center rounded-xl hover:bg-[var(--color-hover)] transition-colors duration-fast focus-ring"
        aria-label={count > 0 ? `${count} unread notifications` : 'Notifications'}
      >
        <Bell className="h-5 w-5 text-muted-foreground" />
        {count > 0 && (
          <span className="absolute -right-0.5 -top-0.5">
            <Badge variant="danger" size="xs">
              {count > 99 ? '99+' : count}
            </Badge>
          </span>
        )}
      </button>

      <BottomSheet
        open={open}
        onClose={() => setOpen(false)}
        title="Notifications"
        height="medium"
        headerAction={
          <Link
            href="/notifications"
            onClick={() => setOpen(false)}
            className="text-xs font-medium text-primary hover:text-primary/80 transition-colors"
          >
            View all
          </Link>
        }
      >
        {notifications === null ? (
          <div className="flex flex-col gap-3 px-4 py-4 animate-pulse">
            {[1, 2, 3].map((i) => (
              <div key={i} className="h-14 rounded-xl glass-light" />
            ))}
          </div>
        ) : notifications.length === 0 ? (
          <div className="flex flex-col items-center gap-3 px-4 py-12 text-center">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl glass-standard">
              <Inbox className="h-6 w-6 text-muted-foreground" />
            </div>
            <p className="text-sm font-semibold text-foreground">All caught up</p>
            <p className="text-xs text-muted-foreground">No notifications right now</p>
          </div>
        ) : (
          <div className="flex flex-col divide-y divide-border/40 px-2 py-1">
            {notifications.map((n) => (
              <button
                key={n.id}
                type="button"
                onClick={() => openNotification(n)}
                className="flex items-start gap-3 rounded-xl px-2 py-3 text-left transition-colors hover:glass-light focus-ring"
              >
                <span
                  className={cn(
                    'mt-1.5 h-2 w-2 shrink-0 rounded-full',
                    n.status === 'unread' ? 'bg-primary' : 'bg-transparent'
                  )}
                />
                <div className="min-w-0 flex-1">
                  <p className={cn(
                    'truncate text-sm leading-snug',
                    n.status === 'unread' ? 'font-semibold text-foreground' : 'font-medium text-foreground/75'
                  )}>
                    {n.title}
                  </p>
                  {n.body && (
                    <p className="mt-0.5 line-clamp-1 text-xs text-muted-foreground">{n.body}</p>
                  )}
                  <p className="mt-0.5 text-[10px] text-muted-foreground">
                    {formatRelativeTime(n.created_at)}
                  </p>
                </div>
                {n.priority !== 'normal' && n.priority !== 'low' && (
                  <StatusChip status={n.priority} size="xs" className="mt-0.5 shrink-0" />
                )}
              </button>
            ))}
          </div>
        )}
      </BottomSheet>
    </>
  )
}
