import { NextRequest, NextResponse } from 'next/server'
import QRCode from 'qrcode'
import { createClient } from '@/lib/supabase/server'

interface Props { params: Promise<{ token: string }> }

export async function GET(req: NextRequest, { params }: Props) {
  const { token } = await params
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  // Verify the invitation exists and belongs to a property the user is a member of
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: inv } = await (supabase as any)
    .from('property_invitations')
    .select('token, property_id, email, role')
    .eq('token', token)
    .eq('status', 'pending')
    .maybeSingle()

  if (!inv) return NextResponse.json({ error: 'Invitation not found' }, { status: 404 })

  const { data: membership } = await supabase
    .from('property_members')
    .select('id')
    .eq('property_id', inv.property_id)
    .eq('user_id', user.id)
    .eq('status', 'active')
    .maybeSingle()

  if (!membership) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const inviteUrl = `${process.env.NEXT_PUBLIC_APP_URL ?? 'https://app.prvhouse.com'}/invite/${token}`

  const svg = await QRCode.toString(inviteUrl, {
    type: 'svg',
    width: 200,
    margin: 2,
    color: { dark: '#1a1a2e', light: '#ffffff' },
  })

  return new NextResponse(svg, {
    headers: { 'Content-Type': 'image/svg+xml', 'Cache-Control': 'no-store' },
  })
}
