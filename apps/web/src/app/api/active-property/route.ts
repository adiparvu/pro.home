import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { ACTIVE_PROPERTY_COOKIE } from '@/lib/active-property'

/** Persists the user's active property selection (validated against membership). */
export async function POST(request: Request) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { propertyId } = await request.json().catch(() => ({}))
  if (!propertyId || typeof propertyId !== 'string') {
    return NextResponse.json({ error: 'propertyId required' }, { status: 400 })
  }

  const { data: membership } = await supabase
    .from('property_members')
    .select('id')
    .eq('property_id', propertyId)
    .eq('user_id', user.id)
    .eq('status', 'active')
    .maybeSingle() as { data: { id: string } | null; error: unknown }

  if (!membership) {
    return NextResponse.json({ error: 'Not a member of this property' }, { status: 403 })
  }

  const response = NextResponse.json({ ok: true })
  response.cookies.set(ACTIVE_PROPERTY_COOKIE, propertyId, {
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
    maxAge: 60 * 60 * 24 * 365,
    path: '/',
  })
  return response
}
