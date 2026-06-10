'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { toast } from '@/hooks/use-toast'
import type { Notification } from '@/lib/supabase/types'

/**
 * Live notification stream. Subscribes to the user's notification inserts
 * via Supabase Realtime: new notifications surface instantly as toasts and
 * the server components re-render so badges stay current — no polling.
 */
export function RealtimeNotifications({ userId }: { userId: string }) {
  const router = useRouter()

  React.useEffect(() => {
    const supabase = createClient()
    const channel = supabase
      .channel(`notifications:${userId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'notifications',
          filter: `user_id=eq.${userId}`,
        },
        (payload) => {
          const n = payload.new as Notification
          toast.info(n.title, n.body ?? undefined)
          router.refresh()
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [userId, router])

  return null
}
