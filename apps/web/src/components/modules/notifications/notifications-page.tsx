'use client'

import * as React from 'react'
import { Bell, CheckCheck, Wrench, Zap, Shield, Archive, Home, Sparkles, Info } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import type { Notification } from '@/lib/supabase/types'
import { PageHeader } from '@/components/layout/page-header'
import { Badge } from '@/components/ui/badge'
import { formatRelativeTime } from '@/lib/utils'
import { cn } from '@/lib/utils'

interface NotificationsPageProps {
  notifications: Notification[]
  userId: string
}

const MODULE_ICONS: Record<string, React.ComponentType<{ className?: string }>> = {
  maintenance: Wrench,
  energy: Zap,
  security: Shield,
  inventory: Archive,
  home: Home,
  aria: Sparkles,
}

const PRIORITY_VARIANTS = {
  critical: 'critical',
  high: 'danger',
  normal: 'neutral',
  low: 'neutral',
} as const

export function NotificationsPage({ notifications: initial, userId }: NotificationsPageProps) {
  const router = useRouter()
  const [notifications, setNotifications] = React.useState(initial)
  const [isMarkingAll, setIsMarkingAll] = React.useState(false)

  const unreadCount = notifications.filter((n) => n.status === 'unread').length

  async function markAllRead() {
    setIsMarkingAll(true)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any)
      .from('notifications')
      .update({ status: 'read', read_at: new Date().toISOString() })
      .eq('user_id', userId)
      .eq('status', 'unread')

    setNotifications((prev) => prev.map((n) => n.status === 'unread' ? { ...n, status: 'read' as const } : n))
    setIsMarkingAll(false)
    router.refresh()
  }

  async function markRead(id: string) {
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any)
      .from('notifications')
      .update({ status: 'read', read_at: new Date().toISOString() })
      .eq('id', id)

    setNotifications((prev) => prev.map((n) => n.id === id ? { ...n, status: 'read' as const } : n))
  }

  return (
    <>
      <PageHeader
        title="Notifications"
        action={
          unreadCount > 0
            ? { label: 'Mark all read', href: '#', onClick: markAllRead }
            : undefined
        }
      />

      <div className="flex flex-col pb-[88px] md:pb-0">
        {notifications.length === 0 ? (
          <EmptyState />
        ) : (
          <div className="flex flex-col divide-y divide-border/50">
            {notifications.map((notification) => (
              <NotificationRow
                key={notification.id}
                notification={notification}
                onRead={markRead}
              />
            ))}
          </div>
        )}
      </div>
    </>
  )
}

function NotificationRow({
  notification,
  onRead,
}: {
  notification: Notification
  onRead: (id: string) => void
}) {
  const isUnread = notification.status === 'unread'
  const ModuleIcon = (notification.module && MODULE_ICONS[notification.module]) || Info

  function handleClick() {
    if (isUnread) onRead(notification.id)
  }

  return (
    <button
      type="button"
      onClick={handleClick}
      className={cn(
        'flex items-start gap-4 px-4 py-4 md:px-6 text-left transition-colors hover:bg-[var(--color-hover)] focus-ring w-full',
        isUnread && 'bg-primary/5'
      )}
    >
      <div className={cn(
        'flex h-10 w-10 shrink-0 items-center justify-center rounded-xl',
        isUnread ? 'bg-primary/15' : 'glass-light'
      )}>
        <ModuleIcon className={cn('h-5 w-5', isUnread ? 'text-primary' : 'text-muted-foreground')} />
      </div>

      <div className="flex-1 min-w-0">
        <div className="flex items-start justify-between gap-2">
          <p className={cn('text-sm leading-snug', isUnread ? 'font-semibold text-foreground' : 'font-medium text-foreground/80')}>
            {notification.title}
          </p>
          <div className="flex shrink-0 items-center gap-1.5">
            {notification.priority !== 'normal' && (
              <Badge variant={PRIORITY_VARIANTS[notification.priority]} size="xs">
                {notification.priority}
              </Badge>
            )}
            {isUnread && (
              <span className="h-2 w-2 rounded-full bg-primary shrink-0" />
            )}
          </div>
        </div>
        {notification.body && (
          <p className="mt-0.5 text-xs text-muted-foreground line-clamp-2">{notification.body}</p>
        )}
        <p className="mt-1 text-[10px] text-muted-foreground">
          {formatRelativeTime(notification.created_at)}
        </p>
      </div>
    </button>
  )
}

function EmptyState() {
  return (
    <div className="flex flex-col items-center gap-3 py-20 text-center px-4">
      <div className="flex h-14 w-14 items-center justify-center rounded-2xl glass-standard">
        <Bell className="h-7 w-7 text-muted-foreground" />
      </div>
      <p className="font-semibold text-foreground">All caught up</p>
      <p className="text-sm text-muted-foreground max-w-[200px]">
        You have no notifications right now
      </p>
    </div>
  )
}
