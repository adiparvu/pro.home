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
      max_tokens: 300,
      messages: [{
        role: 'user',
        content: [
          {
            type: 'image',
            source: { type: 'base64', media_type: mime_type, data: image_base64 },
          },
          {
            type: 'text',
            text: 'Extract from this receipt: merchant name, total amount (number only), currency (3-letter code, default EUR), date (YYYY-MM-DD), category (one of: maintenance/utilities/groceries/services/renovation/insurance/tax/other). Respond with JSON only: { merchant, amount, currency, date, category }',
          },
        ],
      }],
    })

    const text = msg.content[0]?.type === 'text' ? msg.content[0].text.trim() : ''
    const match = text.match(/\{[\s\S]*\}/)
    if (!match) return NextResponse.json({ error: 'Could not parse receipt' }, { status: 422 })
    const parsed = JSON.parse(match[0]) as {
      merchant?: string
      amount?: number
      currency?: string
      date?: string
      category?: string
    }
    return NextResponse.json({ result: parsed })
  } catch (err) {
    if (err instanceof SyntaxError) {
      return NextResponse.json({ error: 'Could not parse receipt response as JSON' }, { status: 422 })
    }
    const message = err instanceof Error ? err.message : 'OCR failed'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
