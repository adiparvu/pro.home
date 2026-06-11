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

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { count } = await (supabase as any)
    .from('leases')
    .select('id', { count: 'exact', head: true })
    .eq('property_id', propertyId)
    .eq('status', 'active')

  return NextResponse.json({ count: count ?? 0 })
}
