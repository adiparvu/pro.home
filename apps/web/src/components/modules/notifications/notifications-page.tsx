'use client'

import * as React from 'react'
import { Bell, Wrench, Zap, Shield, Archive, Home, Sparkles, Info, Trash2, Flower2, FolderOpen, Banknote, ExternalLink } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import type { Notification } from '@/lib/supabase/types'
import { PageHeader } from '@/components/layout/page-header'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
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
  garden: Flower2,
  documents: FolderOpen,
  finances: Banknote,
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
  const [isClearingRead, setIsClearingRead] = React.useState(false)

  const unreadCount = notifications.filter((n) => n.status === 'unread').length
  const readCount = notifications.filter((n) => n.status === 'read').length

  async function markAllRead() {
    setIsMarkingAll(true)
    setNotifications((prev) =>
      prev.map((n) => (n.status === 'unread' ? { ...n, status: 'read' as const } : n))
    )
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any)
      .from('notifications')
      .update({ status: 'read', read_at: new Date().toISOString() })
      .eq('user_id', userId)
      .eq('status', 'unread')
    setIsMarkingAll(false)
    router.refresh()
  }

  async function clearReadNotifications() {
    setIsClearingRead(true)
    setNotifications((prev) => prev.filter((n) => n.status !== 'read'))
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any)
      .from('notifications')
      .delete()
      .eq('user_id', userId)
      .eq('status', 'read')
    setIsClearingRead(false)
    router.refresh()
  }

  async function markRead(id: string) {
    setNotifications((prev) =>
      prev.map((n) => (n.id === id ? { ...n, status: 'read' as const } : n))
    )
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any)
      .from('notifications')
      .update({ status: 'read', read_at: new Date().toISOString() })
      .eq('id', id)
  }

  async function deleteNotification(id: string) {
    setNotifications((prev) => prev.filter((n) => n.id !== id))
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('notifications').delete().eq('id', id)
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
        {readCount > 0 && (
          <div className="flex items-center justify-between border-b border-border/30 px-4 py-2 md:px-6">
            <p className="text-xs text-muted-foreground">{readCount} read</p>
            <Button
              variant="ghost"
              size="sm"
              loading={isClearingRead}
              onClick={clearReadNotifications}
              className="h-7 text-xs text-muted-foreground hover:text-destructive"
            >
              <Trash2 className="h-3 w-3" />
              Clear read
            </Button>
          </div>
        )}

        {notifications.length === 0 ? (
          <EmptyState />
        ) : (
          <div className="flex flex-col divide-y divide-border/50">
            {notifications.map((notification) => (
              <NotificationRow
                key={notification.id}
                notification={notification}
                onRead={markRead}
                onDelete={deleteNotification}
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
  onDelete,
}: {
  notification: Notification
  onRead: (id: string) => void
  onDelete: (id: string) => void
}) {
  const router = useRouter()
  const isUnread = notification.status === 'unread'
  const ModuleIcon = (notification.module && MODULE_ICONS[notification.module]) || Info

  function handleClick() {
    if (isUnread) onRead(notification.id)
    if (notification.action_url) router.push(notification.action_url)
  }

  const isClickable = isUnread || !!notification.action_url

  return (
    <div className={cn('flex items-start gap-3 px-4 py-4 md:px-6', isUnread && 'bg-primary/5')}>
      <button
        type="button"
        onClick={handleClick}
        className={cn(
          'flex h-10 w-10 shrink-0 items-center justify-center rounded-xl transition-colors',
          isClickable ? 'bg-primary/15 hover:bg-primary/25 cursor-pointer' : 'glass-light cursor-default'
        )}
        aria-label={isUnread ? 'Mark as read and open' : notification.action_url ? 'Open' : undefined}
        disabled={!isClickable}
      >
        <ModuleIcon className={cn('h-5 w-5', isClickable ? 'text-primary' : 'text-muted-foreground')} />
      </button>

      <div
        className={cn('min-w-0 flex-1', isClickable && 'cursor-pointer')}
        role={isClickable ? 'button' : undefined}
        onClick={isClickable ? handleClick : undefined}
      >
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
            {isUnread && <span className="h-2 w-2 shrink-0 rounded-full bg-primary" />}
          </div>
        </div>
        {notification.body && (
          <p className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">{notification.body}</p>
        )}
        <div className="mt-1 flex items-center gap-2">
          <span className="text-[10px] text-muted-foreground">
            {formatRelativeTime(notification.created_at)}
          </span>
          {notification.action_url && (
            <span className="flex items-center gap-0.5 text-[10px] text-primary/60">
              <ExternalLink className="h-2.5 w-2.5" />
              Open
            </span>
          )}
        </div>
      </div>

      <button
        type="button"
        onClick={() => onDelete(notification.id)}
        className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:glass-light hover:text-destructive"
        aria-label="Delete notification"
      >
        <Trash2 className="h-3.5 w-3.5" />
      </button>
    </div>
  )
}

function EmptyState() {
  return (
    <div className="flex flex-col items-center gap-3 px-4 py-20 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-2xl glass-standard">
        <Bell className="h-7 w-7 text-muted-foreground" />
      </div>
      <p className="font-semibold text-foreground">All caught up</p>
      <p className="max-w-[200px] text-sm text-muted-foreground">
        You have no notifications right now
      </p>
    </div>
  )
}
