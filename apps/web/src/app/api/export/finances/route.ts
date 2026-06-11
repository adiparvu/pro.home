import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'

function csvCell(v: unknown): string {
  if (v == null) return ''
  const s = String(v)
  if (s.includes(',') || s.includes('"') || s.includes('\n')) {
    return `"${s.replace(/"/g, '""')}"`
  }
  return s
}

export async function GET() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return new NextResponse('Unauthorized', { status: 401 })

  const property = await getActiveProperty(supabase, user.id)
  if (!property) return new NextResponse('No property', { status: 404 })

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: records } = await (supabase as any)
    .from('financial_records')
    .select('date,type,category,title,amount,currency,description,tags,is_recurring,recurrence_interval')
    .eq('property_id', property.id)
    .order('date', { ascending: false })
    .limit(2000) as { data: Array<{
      date: string; type: string; category: string; title: string
      amount: number; currency: string; description: string | null
      tags: string[] | null; is_recurring: boolean | null; recurrence_interval: string | null
    }> | null }

  const header = ['Date', 'Type', 'Category', 'Title', 'Amount', 'Currency', 'Description', 'Tags', 'Recurring', 'Interval']
  const rows = (records ?? []).map((r) => [
    r.date,
    r.type,
    r.category,
    r.title,
    r.amount,
    r.currency,
    r.description ?? '',
    (r.tags ?? []).join('|'),
    r.is_recurring ? 'yes' : 'no',
    r.recurrence_interval ?? '',
  ].map(csvCell).join(','))

  const csv = [header.join(','), ...rows].join('\n')
  const filename = `finances-${property.id}-${new Date().toISOString().split('T')[0]}.csv`

  return new NextResponse(csv, {
    headers: {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="${filename}"`,
    },
  })
}
