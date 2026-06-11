import { type NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import type { InventoryItem } from '@/lib/supabase/types'

export async function GET(req: NextRequest) {
  // Auth guard
  const cronSecret = req.headers.get('x-cron-secret')
  if (!cronSecret || cronSecret !== process.env.CRON_SECRET) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const supabase = await createClient()

  // Date helpers
  const now = new Date()
  const today = now.toISOString().split('T')[0]

  const futureDate = new Date(now)
  futureDate.setDate(futureDate.getDate() + 30)
  const future30 = futureDate.toISOString().split('T')[0]

  const twentyFiveDaysAgo = new Date(now)
  twentyFiveDaysAgo.setDate(twentyFiveDaysAgo.getDate() - 25)
  const twentyFiveDaysAgoISO = twentyFiveDaysAgo.toISOString()

  // Query items with warranty expiring in the next 30 days
  const { data: items, error: itemsError } = await supabase
    .from('inventory_items')
    .select('*')
    .gte('warranty_expires', today)
    .lte('warranty_expires', future30) as {
    data: InventoryItem[] | null
    error: unknown
  }

  if (itemsError) {
    console.error('[warranty-check] Failed to query inventory_items:', itemsError)
    return NextResponse.json({ error: 'Failed to query inventory items' }, { status: 500 })
  }

  const expiringItems = items ?? []
  let notified = 0

  for (const item of expiringItems) {
    // Skip items without a user to notify
    if (!item.added_by) continue

    // Check if a notification was already sent in the last 25 days
    const { data: existing } = await (supabase as any)
      .from('notifications')
      .select('id')
      .eq('resource_id', item.id)
      .eq('resource_type', 'inventory_item')
      .gte('created_at', twentyFiveDaysAgoISO)
      .limit(1)

    if (existing && existing.length > 0) continue

    // Insert new notification
    const { error: insertError } = await (supabase as any)
      .from('notifications')
      .insert({
        property_id: item.property_id,
        user_id: item.added_by,
        title: 'Warranty expiring soon',
        body: `${item.name} warranty expires on ${item.warranty_expires}`,
        priority: 'normal',
        status: 'unread',
        module: 'inventory',
        resource_type: 'inventory_item',
        resource_id: item.id,
        action_url: `/inventory/${item.id}`,
        metadata: {},
      })

    if (insertError) {
      console.error(`[warranty-check] Failed to insert notification for item ${item.id}:`, insertError)
    } else {
      notified++
    }
  }

  return NextResponse.json({ processed: expiringItems.length, notified })
}
