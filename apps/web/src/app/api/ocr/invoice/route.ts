import { NextRequest, NextResponse } from 'next/server'
import Anthropic from '@anthropic-ai/sdk'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY ?? '' })

const ALLOWED_MIME_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'] as const
type AllowedMimeType = typeof ALLOWED_MIME_TYPES[number]

function isAllowedMimeType(value: string): value is AllowedMimeType {
  return (ALLOWED_MIME_TYPES as readonly string[]).includes(value)
}

export async function POST(req: NextRequest) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const property = await getActiveProperty(supabase, user.id)
  if (!property) return NextResponse.json({ error: 'No active property' }, { status: 400 })

  const body = await req.json() as { image_base64?: string; mime_type?: string }
  const { image_base64, mime_type } = body

  if (!image_base64 || !mime_type) {
    return NextResponse.json({ error: 'image_base64 and mime_type are required' }, { status: 400 })
  }

  if (!isAllowedMimeType(mime_type)) {
    return NextResponse.json(
      { error: `mime_type must be one of: ${ALLOWED_MIME_TYPES.join(', ')}` },
      { status: 400 }
    )
  }

  try {
    const msg = await anthropic.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 400,
      messages: [{
        role: 'user',
        content: [
          {
            type: 'image',
            source: { type: 'base64', media_type: mime_type, data: image_base64 },
          },
          {
            type: 'text',
            text: `Extract from this contractor invoice:
- vendor (contractor/company name)
- invoice_number
- amount (numeric total)
- currency (3-letter code, default EUR)
- date (YYYY-MM-DD)
- description (what work was done, max 100 chars)
- category (one of: plumbing, electrical, hvac, painting, flooring, roofing, landscaping, cleaning, pest_control, general_maintenance, other)
Return JSON only: { vendor, invoice_number, amount, currency, date, description, category }`,
          },
        ],
      }],
    })

    const text = msg.content[0]?.type === 'text' ? msg.content[0].text.trim() : ''
    const match = text.match(/\{[\s\S]*\}/)

    if (!match) {
      // Return best-effort partial data
      return NextResponse.json({
        result: {
          vendor: null,
          invoice_number: null,
          amount: null,
          currency: 'EUR',
          date: null,
          description: null,
          category: 'other',
        },
        warning: 'Could not parse invoice data',
      })
    }

    try {
      const parsed = JSON.parse(match[0]) as {
        vendor?: string | null
        invoice_number?: string | null
        amount?: number | null
        currency?: string | null
        date?: string | null
        description?: string | null
        category?: string | null
      }
      return NextResponse.json({ result: parsed })
    } catch {
      // Best-effort partial data on parse failure
      return NextResponse.json({
        result: {
          vendor: null,
          invoice_number: null,
          amount: null,
          currency: 'EUR',
          date: null,
          description: null,
          category: 'other',
        },
        warning: 'Could not parse invoice response as JSON',
      })
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : 'OCR failed'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
