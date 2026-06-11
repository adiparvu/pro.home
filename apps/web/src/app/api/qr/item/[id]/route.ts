import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { qrWithLogo } from '@/lib/qr-with-logo'

interface Props { params: Promise<{ id: string }> }

export async function GET(req: NextRequest, { params }: Props) {
  const { id } = await params
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  // Verify the item exists and belongs to a property the user is a member of
  const { data: item } = await supabase
    .from('inventory_items')
    .select('id, property_id')
    .eq('id', id)
    .single() as { data: { id: string; property_id: string } | null; error: unknown }

  if (!item) return NextResponse.json({ error: 'Not found' }, { status: 404 })

  const { data: membership } = await supabase
    .from('property_members')
    .select('id')
    .eq('property_id', item.property_id)
    .eq('user_id', user.id)
    .eq('status', 'active')
    .maybeSingle()

  if (!membership) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const url = `${process.env.NEXT_PUBLIC_APP_URL ?? 'https://app.prvhouse.com'}/i/${id}`
  const svg = await qrWithLogo(url, { width: 200, margin: 2, dark: '#0D1420', light: '#ffffff' })

  return new NextResponse(svg, {
    headers: { 'Content-Type': 'image/svg+xml', 'Cache-Control': 'no-store' },
  })
}
