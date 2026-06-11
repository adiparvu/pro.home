import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function POST(req: NextRequest) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const form = await req.formData()
  const file = form.get('file') as File | null
  const propertyId = form.get('property_id') as string | null
  const itemType = form.get('item_type') as string | null
  const itemId = form.get('item_id') as string | null

  if (!file || !propertyId || !itemType || !itemId) {
    return NextResponse.json({ error: 'Missing required fields: file, property_id, item_type, item_id' }, { status: 400 })
  }
  if (!['task', 'defect'].includes(itemType)) {
    return NextResponse.json({ error: 'item_type must be "task" or "defect"' }, { status: 400 })
  }
  if (file.size > 10 * 1024 * 1024) {
    return NextResponse.json({ error: 'File too large (max 10 MB)' }, { status: 400 })
  }

  // Verify user is a member of this property
  const { data: membership } = await supabase
    .from('property_members')
    .select('id')
    .eq('property_id', propertyId)
    .eq('user_id', user.id)
    .eq('status', 'active')
    .maybeSingle()
  if (!membership) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const sanitizedFilename = file.name.replace(/[^a-z0-9._-]/gi, '_')
  const path = `${propertyId}/${itemType}/${itemId}/${Date.now()}-${sanitizedFilename}`
  const bytes = await file.arrayBuffer()

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { error: uploadError } = await (supabase as any).storage
    .from('property-photos')
    .upload(path, bytes, { contentType: file.type, upsert: false })

  if (uploadError) {
    return NextResponse.json({ error: uploadError.message }, { status: 500 })
  }

  // Generate a signed URL valid for 1 hour
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: signData, error: signError } = await (supabase as any).storage
    .from('property-photos')
    .createSignedUrl(path, 3600)

  if (signError || !signData) {
    return NextResponse.json({ error: 'Failed to generate signed URL' }, { status: 500 })
  }

  return NextResponse.json({ path, signedUrl: signData.signedUrl })
}
