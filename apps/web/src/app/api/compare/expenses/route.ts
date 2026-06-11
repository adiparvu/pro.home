import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function GET(req: NextRequest) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const propertyId = req.nextUrl.searchParams.get('property_id')
  if (!propertyId) return NextResponse.json({ error: 'Missing property_id' }, { status: 400 })

  const { data: membership } = await supabase
    .from('property_members')
    .select('id')
    .eq('property_id', propertyId)
    .eq('user_id', user.id)
    .eq('status', 'active')
    .maybeSingle()
  if (!membership) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const now = new Date()
  const yearStart = `${now.getFullYear()}-01-01`

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data } = await (supabase as any)
    .from('financial_records')
    .select('amount')
    .eq('property_id', propertyId)
    .eq('type', 'expense')
    .gte('date', yearStart)

  const total = (data ?? []).reduce((sum: number, r: { amount: number }) => sum + (r.amount ?? 0), 0)
  return NextResponse.json({ total })
}
