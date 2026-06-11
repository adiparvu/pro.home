import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function POST(req: NextRequest) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  let body: { item_id?: string; target_property_id?: string }
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 })
  }

  const { item_id, target_property_id } = body
  if (!item_id || !target_property_id) {
    return NextResponse.json({ error: 'item_id and target_property_id are required' }, { status: 400 })
  }

  // Fetch item to get current property_id
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: item, error: itemError } = await (supabase as any)
    .from('inventory_items')
    .select('id, property_id')
    .eq('id', item_id)
    .single() as { data: { id: string; property_id: string } | null; error: unknown }

  if (itemError || !item) {
    return NextResponse.json({ error: 'Item not found' }, { status: 404 })
  }

  const source_property_id = item.property_id

  if (source_property_id === target_property_id) {
    return NextResponse.json({ error: 'Item is already in the target property' }, { status: 400 })
  }

  // Verify user is active member of source property
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: sourceMember } = await (supabase as any)
    .from('property_members')
    .select('id')
    .eq('property_id', source_property_id)
    .eq('user_id', user.id)
    .eq('status', 'active')
    .single()

  if (!sourceMember) {
    return NextResponse.json({ error: 'Not a member of the source property' }, { status: 403 })
  }

  // Verify user is active member of target property
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: targetMember } = await (supabase as any)
    .from('property_members')
    .select('id')
    .eq('property_id', target_property_id)
    .eq('user_id', user.id)
    .eq('status', 'active')
    .single()

  if (!targetMember) {
    return NextResponse.json({ error: 'Not a member of the target property' }, { status: 403 })
  }

  // Perform the transfer
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { error: updateError } = await (supabase as any)
    .from('inventory_items')
    .update({ property_id: target_property_id })
    .eq('id', item_id)

  if (updateError) {
    return NextResponse.json({ error: updateError.message }, { status: 500 })
  }

  return NextResponse.json({ success: true })
}
