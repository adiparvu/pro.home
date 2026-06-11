import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'

function escapeIcs(s: string) {
  return s.replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\n/g, '\\n')
}

function foldLine(line: string): string {
  const chunks: string[] = []
  while (line.length > 75) {
    chunks.push(line.slice(0, 75))
    line = ' ' + line.slice(75)
  }
  chunks.push(line)
  return chunks.join('\r\n')
}

export async function GET() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return new NextResponse('Unauthorized', { status: 401 })

  const property = await getActiveProperty(supabase, user.id)
  if (!property) return new NextResponse('No property', { status: 404 })

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: tasks } = await (supabase as any)
    .from('maintenance_tasks')
    .select('id,title,description,due_date,priority,status,category')
    .eq('property_id', property.id)
    .not('due_date', 'is', null)
    .neq('status', 'cancelled')
    .neq('status', 'completed')
    .order('due_date', { ascending: true })
    .limit(200) as { data: Array<{
      id: string; title: string; description: string | null
      due_date: string; priority: string; status: string; category: string
    }> | null }

  const now = new Date().toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z'
  const lines: string[] = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    `PRODID:-//PRV HOUSE//Maintenance Calendar//EN`,
    `X-WR-CALNAME:${escapeIcs(property.name)} Maintenance`,
    'X-WR-TIMEZONE:UTC',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
  ]

  for (const t of tasks ?? []) {
    const dtStamp = now
    const uid = `${t.id}@prvhouse.app`
    const dtStart = t.due_date.replace(/-/g, '') + 'T090000Z'
    const dtEnd = t.due_date.replace(/-/g, '') + 'T100000Z'
    const summary = `[${t.priority.toUpperCase()}] ${t.title}`
    const desc = [
      t.description ?? '',
      `Status: ${t.status}`,
      `Category: ${t.category}`,
      `Priority: ${t.priority}`,
    ].filter(Boolean).join('\\n')

    lines.push('BEGIN:VEVENT')
    lines.push(foldLine(`UID:${uid}`))
    lines.push(foldLine(`DTSTAMP:${dtStamp}`))
    lines.push(foldLine(`DTSTART:${dtStart}`))
    lines.push(foldLine(`DTEND:${dtEnd}`))
    lines.push(foldLine(`SUMMARY:${escapeIcs(summary)}`))
    lines.push(foldLine(`DESCRIPTION:${escapeIcs(desc)}`))
    lines.push(foldLine(`CATEGORIES:${escapeIcs(t.category)}`))
    lines.push('END:VEVENT')
  }

  lines.push('END:VCALENDAR')

  return new NextResponse(lines.join('\r\n'), {
    headers: {
      'Content-Type': 'text/calendar; charset=utf-8',
      'Content-Disposition': `attachment; filename="maintenance-${property.id}.ics"`,
      'Cache-Control': 'no-cache, no-store',
    },
  })
}
