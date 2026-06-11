import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function GET(req: NextRequest) {
  if (req.headers.get('x-cron-secret') !== process.env.CRON_SECRET) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  try {
    const supabase = await createClient()

    const today = new Date()
    const todayDay = today.getDate()
    const year = today.getFullYear()
    const month = today.getMonth() + 1 // 1-based

    // Fetch active leases
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: leases, error: leasesError } = await (supabase as any)
      .from('leases')
      .select('id, property_id, tenant_name, tenant_user_id, monthly_rent, currency, payment_day')
      .eq('status', 'active')

    if (leasesError) throw leasesError

    let sent = 0

    for (const lease of (leases ?? [])) {
      const paymentDay: number = lease.payment_day ?? 1
      const daysUntil = paymentDay - todayDay

      // Only notify if within 3 days before due
      if (daysUntil < 0 || daysUntil > 3) continue

      // Check if notification already sent this month
      const monthStart = `${year}-${String(month).padStart(2, '0')}-01`
      const monthEnd = `${year}-${String(month).padStart(2, '0')}-31`

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: existing } = await (supabase as any)
        .from('notifications')
        .select('id')
        .eq('resource_type', 'lease')
        .eq('resource_id', lease.id)
        .eq('module', 'rent_reminder')
        .gte('created_at', monthStart)
        .lte('created_at', monthEnd)
        .limit(1)

      if (existing && existing.length > 0) continue

      // Create notification
      const userId = lease.tenant_user_id
      if (!userId) continue

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { error: insertError } = await (supabase as any)
        .from('notifications')
        .insert({
          user_id: userId,
          property_id: lease.property_id,
          title: 'Rent due soon',
          body: `Rent of ${lease.monthly_rent} ${lease.currency ?? ''} due on the ${paymentDay}th for ${lease.tenant_name}`.trim(),
          priority: 'normal',
          status: 'unread',
          module: 'rent_reminder',
          resource_type: 'lease',
          resource_id: lease.id,
          metadata: {},
        })

      if (insertError) {
        console.error('Failed to insert notification for lease', lease.id, insertError)
      } else {
        sent++
      }
    }

    return NextResponse.json({ ok: true, sent })
  } catch (err) {
    console.error('rent-reminder cron error', err)
    return NextResponse.json({ error: String(err) }, { status: 500 })
  }
}
