import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function POST(req: Request) {
  try {
    const body = await req.json() as {
      portal_id: string
      property_id: string
      tenant_name: string
      tenant_email?: string | null
      title: string
      description?: string | null
      category?: string | null
      priority?: string | null
    }

    const { portal_id, property_id, tenant_name, tenant_email, title, description, category, priority } = body

    if (!portal_id || !property_id || !tenant_name?.trim() || !title?.trim()) {
      return NextResponse.json({ error: 'Missing required fields' }, { status: 400 })
    }

    const supabase = await createClient()

    // Validate portal exists and is active
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: portal, error: portalError } = await (supabase as any)
      .from('tenant_portals')
      .select('id, active')
      .eq('id', portal_id)
      .eq('property_id', property_id)
      .single()

    if (portalError || !portal) {
      return NextResponse.json({ error: 'Portal not found' }, { status: 404 })
    }

    if (!portal.active) {
      return NextResponse.json({ error: 'Portal is inactive' }, { status: 403 })
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error: insertError } = await (supabase as any)
      .from('tenant_requests')
      .insert({
        portal_id,
        property_id,
        tenant_name: tenant_name.trim(),
        tenant_email: tenant_email ?? null,
        title: title.trim(),
        description: description ?? null,
        category: category ?? null,
        priority: priority ?? null,
        status: 'pending',
      })

    if (insertError) {
      return NextResponse.json({ error: insertError.message }, { status: 500 })
    }

    return NextResponse.json({ success: true })
  } catch (err) {
    return NextResponse.json({ error: String(err) }, { status: 500 })
  }
}
