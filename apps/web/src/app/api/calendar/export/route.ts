import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'

function icsDate(d: string | Date): string {
  const dt = typeof d === 'string' ? new Date(d) : d
  if (isNaN(dt.getTime())) return ''
  return dt.toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z'
}

function escIcs(s: string): string {
  return s.replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\n/g, '\\n')
}

function makeEvent(uid: string, summary: string, dtstart: string, description?: string): string {
  if (!dtstart) return ''
  return [
    'BEGIN:VEVENT',
    `UID:${uid}`,
    `DTSTAMP:${icsDate(new Date())}`,
    `DTSTART;VALUE=DATE:${dtstart.replace('T', '').slice(0, 8)}`,
    `SUMMARY:${escIcs(summary)}`,
    description ? `DESCRIPTION:${escIcs(description)}` : '',
    'END:VEVENT',
  ].filter(Boolean).join('\r\n')
}

export async function GET() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const property = await getActiveProperty(supabase, user.id)
  if (!property) return NextResponse.json({ error: 'No property' }, { status: 404 })

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sb = supabase as any
  const [tasksRes, docsRes, inventoryRes, leasesRes] = await Promise.all([
    sb
      .from('maintenance_tasks')
      .select('id, title, due_date, category, priority')
      .eq('property_id', property.id)
      .not('due_date', 'is', null)
      .neq('status', 'done'),

    sb
      .from('documents')
      .select('id, name, expires_at, category')
      .eq('property_id', property.id)
      .not('expires_at', 'is', null),

    sb
      .from('inventory_items')
      .select('id, name, warranty_expires, category')
      .eq('property_id', property.id)
      .not('warranty_expires', 'is', null),

    sb
      .from('leases')
      .select('id, tenant_name, end_date, status')
      .eq('property_id', property.id)
      .not('end_date', 'is', null)
      .neq('status', 'terminated'),
  ])

  const events: string[] = []

  for (const t of tasksRes.data ?? []) {
    if (!t.due_date) continue
    const dateStr = t.due_date.slice(0, 10).replace(/-/g, '')
    events.push(makeEvent(
      `task-${t.id}@prvhouse`,
      `[Task] ${t.title}`,
      dateStr,
      `Category: ${t.category ?? 'General'} | Priority: ${t.priority ?? 'normal'}`,
    ))
  }

  for (const d of docsRes.data ?? []) {
    if (!d.expires_at) continue
    const dateStr = d.expires_at.slice(0, 10).replace(/-/g, '')
    events.push(makeEvent(
      `doc-${d.id}@prvhouse`,
      `[Document expires] ${d.name}`,
      dateStr,
      `Category: ${d.category ?? ''}`,
    ))
  }

  for (const item of inventoryRes.data ?? []) {
    if (!item.warranty_expires) continue
    const dateStr = item.warranty_expires.slice(0, 10).replace(/-/g, '')
    events.push(makeEvent(
      `warranty-${item.id}@prvhouse`,
      `[Warranty expires] ${item.name}`,
      dateStr,
      `Category: ${item.category ?? ''}`,
    ))
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  for (const lease of (leasesRes.data ?? []) as any[]) {
    if (!lease.end_date) continue
    const dateStr = lease.end_date.slice(0, 10).replace(/-/g, '')
    events.push(makeEvent(
      `lease-${lease.id}@prvhouse`,
      `[Lease ends] ${lease.tenant_name ?? 'Tenant'}`,
      dateStr,
    ))
  }

  const validEvents = events.filter(Boolean)

  const ics = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//PRVIO//Property Calendar//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    `X-WR-CALNAME:${escIcs(property.name)} – PRVIO`,
    'X-WR-TIMEZONE:UTC',
    ...validEvents,
    'END:VCALENDAR',
  ].join('\r\n')

  const filename = `prvhouse-${property.name.replace(/[^a-z0-9]/gi, '-').toLowerCase()}.ics`

  return new NextResponse(ics, {
    headers: {
      'Content-Type': 'text/calendar; charset=utf-8',
      'Content-Disposition': `attachment; filename="${filename}"`,
      'Cache-Control': 'no-cache',
    },
  })
}
