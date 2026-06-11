import { type NextRequest, NextResponse } from 'next/server'
import { createClient as createAdminClient } from '@supabase/supabase-js'

export const dynamic = 'force-dynamic'

interface PropertyRow {
  id: string
  name: string
}

interface MemberRow {
  user_id: string
}

export async function GET(req: NextRequest) {
  if (req.headers.get('x-cron-secret') !== process.env.CRON_SECRET) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return NextResponse.json({ error: 'Service role key not configured' }, { status: 503 })
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const db: any = createAdminClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
  )

  const today = new Date()
  const todayISO = today.toISOString().split('T')[0]!

  const in30Days = new Date(today)
  in30Days.setDate(in30Days.getDate() + 30)
  const in30ISO = in30Days.toISOString().split('T')[0]!

  const in60Days = new Date(today)
  in60Days.setDate(in60Days.getDate() + 60)
  const in60ISO = in60Days.toISOString().split('T')[0]!

  // Fetch all active properties
  const { data: properties, error: propError } = (await db
    .from('properties')
    .select('id, name')) as { data: PropertyRow[] | null; error: unknown }

  if (propError) {
    console.error('[daily-digest] Failed to fetch properties:', propError)
    return NextResponse.json({ error: 'Failed to fetch properties' }, { status: 500 })
  }

  let processedProperties = 0
  let notificationsSent = 0

  for (const property of properties ?? []) {
    const pid = property.id

    // Fetch issues in parallel
    const [overdueTasksRes, expiringCertsRes, expiringInsuranceRes, upcomingLeasesRes] =
      await Promise.all([
        // 1. Overdue maintenance tasks (due_date < today, status not done/cancelled)
        db
          .from('maintenance_tasks')
          .select('id, title, due_date')
          .eq('property_id', pid)
          .lt('due_date', todayISO)
          .not('status', 'in', '("done","completed","cancelled")'),

        // 2. Compliance certs expiring in 30 days
        db
          .from('compliance_certificates')
          .select('id, name, expiry_date')
          .eq('property_id', pid)
          .gte('expiry_date', todayISO)
          .lte('expiry_date', in30ISO),

        // 3. Insurance policies expiring in 30 days
        db
          .from('insurance_policies')
          .select('id, policy_name, end_date')
          .eq('property_id', pid)
          .gte('end_date', todayISO)
          .lte('end_date', in30ISO),

        // 4. Upcoming lease end dates (within 60 days)
        db
          .from('leases')
          .select('id, tenant_name, end_date')
          .eq('property_id', pid)
          .eq('status', 'active')
          .gte('end_date', todayISO)
          .lte('end_date', in60ISO),
      ])

    const overdueTasks: { id: string; title: string; due_date: string }[] =
      overdueTasksRes.data ?? []
    const expiringCerts: { id: string; name: string; expiry_date: string }[] =
      expiringCertsRes.data ?? []
    const expiringInsurance: { id: string; policy_name: string; end_date: string }[] =
      expiringInsuranceRes.data ?? []
    const upcomingLeases: { id: string; tenant_name: string; end_date: string }[] =
      upcomingLeasesRes.data ?? []

    // Skip properties with nothing to report
    const hasIssues =
      overdueTasks.length > 0 ||
      expiringCerts.length > 0 ||
      expiringInsurance.length > 0 ||
      upcomingLeases.length > 0

    if (!hasIssues) continue

    processedProperties++

    // Fetch subscribed members for this property
    const { data: members } = (await db
      .from('property_members')
      .select('user_id')
      .eq('property_id', pid)
      .eq('status', 'active')) as { data: MemberRow[] | null }

    if (!members || members.length === 0) continue

    // Build notifications for each issue type per member
    for (const member of members) {
      const uid = member.user_id

      // Overdue tasks
      for (const task of overdueTasks) {
        const { error: insErr } = await db.from('notifications').insert({
          property_id: pid,
          user_id: uid,
          title: 'Overdue maintenance task',
          body: `"${task.title}" was due on ${task.due_date} and is still open.`,
          priority: 'high',
          status: 'unread',
          module: 'daily_digest',
          resource_type: 'maintenance_task',
          resource_id: task.id,
          action_url: `/maintenance`,
          metadata: { digest_type: 'overdue_task' },
        })
        if (!insErr) notificationsSent++
      }

      // Expiring compliance certs
      for (const cert of expiringCerts) {
        const { error: insErr } = await db.from('notifications').insert({
          property_id: pid,
          user_id: uid,
          title: 'Compliance certificate expiring soon',
          body: `"${cert.name}" expires on ${cert.expiry_date}. Renew before it lapses.`,
          priority: 'high',
          status: 'unread',
          module: 'daily_digest',
          resource_type: 'compliance_certificate',
          resource_id: cert.id,
          action_url: `/documents/compliance`,
          metadata: { digest_type: 'expiring_cert' },
        })
        if (!insErr) notificationsSent++
      }

      // Expiring insurance
      for (const policy of expiringInsurance) {
        const { error: insErr } = await db.from('notifications').insert({
          property_id: pid,
          user_id: uid,
          title: 'Insurance policy expiring soon',
          body: `"${policy.policy_name}" expires on ${policy.end_date}. Arrange renewal.`,
          priority: 'high',
          status: 'unread',
          module: 'daily_digest',
          resource_type: 'insurance_policy',
          resource_id: policy.id,
          action_url: `/finances/insurance`,
          metadata: { digest_type: 'expiring_insurance' },
        })
        if (!insErr) notificationsSent++
      }

      // Upcoming lease ends
      for (const lease of upcomingLeases) {
        const { error: insErr } = await db.from('notifications').insert({
          property_id: pid,
          user_id: uid,
          title: 'Lease ending soon',
          body: `${lease.tenant_name ?? 'Tenant'}'s lease ends on ${lease.end_date}. Plan for renewal or vacancy.`,
          priority: 'normal',
          status: 'unread',
          module: 'daily_digest',
          resource_type: 'lease',
          resource_id: lease.id,
          action_url: `/tenant/leases`,
          metadata: { digest_type: 'lease_ending' },
        })
        if (!insErr) notificationsSent++
      }
    }
  }

  // After inserting notifications, trigger push dispatch to deliver them
  if (notificationsSent > 0) {
    const baseUrl = process.env.NEXT_PUBLIC_APP_URL ?? `https://${req.headers.get('host') ?? 'localhost:3000'}`
    try {
      await fetch(`${baseUrl}/api/push/dispatch`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-cron-secret': process.env.CRON_SECRET ?? '',
        },
      })
    } catch (err) {
      console.warn('[daily-digest] Failed to call push dispatch:', err)
    }
  }

  return NextResponse.json({ processed_properties: processedProperties, notifications_sent: notificationsSent })
}
