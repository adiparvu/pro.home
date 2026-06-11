import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function GET() {
  return NextResponse.json({ status: 'ok', timestamp: new Date().toISOString() })
}

interface MeterReadingInput {
  meter_type: string
  value: number
  unit: string
  reading_date?: string
}

interface WebhookBody {
  token: string
  readings: MeterReadingInput[]
}

export async function POST(req: NextRequest) {
  let body: WebhookBody
  try {
    body = await req.json() as WebhookBody
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const { token, readings } = body

  if (!token) {
    return NextResponse.json({ error: 'Missing token' }, { status: 400 })
  }

  if (!Array.isArray(readings) || readings.length === 0) {
    return NextResponse.json({ error: 'readings must be a non-empty array' }, { status: 400 })
  }

  const supabase = await createClient()

  // Verify token exists and is active (no auth — token-based)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: tokenRow, error: tokenError } = await (supabase as any)
    .from('smart_home_tokens')
    .select('id, property_id, active')
    .eq('token', token)
    .single()

  if (tokenError || !tokenRow) {
    return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
  }

  if (!tokenRow.active) {
    return NextResponse.json({ error: 'Token is inactive' }, { status: 403 })
  }

  const propertyId = tokenRow.property_id as string

  // Update last_used_at
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (supabase as any)
    .from('smart_home_tokens')
    .update({ last_used_at: new Date().toISOString() })
    .eq('id', tokenRow.id)

  // Insert meter readings
  const insertRows = readings.map((r) => ({
    property_id: propertyId,
    meter_type: r.meter_type,
    reading: r.value,
    unit: r.unit,
    reading_date: r.reading_date ?? new Date().toISOString().slice(0, 10),
  }))

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { error: insertError } = await (supabase as any)
    .from('meter_readings')
    .insert(insertRows)

  if (insertError) {
    return NextResponse.json({ error: insertError.message }, { status: 500 })
  }

  return NextResponse.json({ received: readings.length, property_id: propertyId })
}
