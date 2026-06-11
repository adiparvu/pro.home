import { NextRequest, NextResponse } from 'next/server'
import Anthropic from '@anthropic-ai/sdk'
import { createClient } from '@/lib/supabase/server'
import { checkRateLimit } from '@/lib/rate-limit'

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY ?? '' })

export async function POST(req: NextRequest) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { allowed } = checkRateLimit(`${user.id}:ocr`, 20, 3600)
  const limited = !allowed
  if (limited) return NextResponse.json({ error: 'Rate limit reached' }, { status: 429 })

  const form = await req.formData()
  const file = form.get('file') as File | null
  if (!file) return NextResponse.json({ error: 'No file provided' }, { status: 400 })
  if (file.size > 5 * 1024 * 1024) return NextResponse.json({ error: 'File too large (max 5 MB)' }, { status: 400 })

  const bytes = await file.arrayBuffer()
  const base64 = Buffer.from(bytes).toString('base64')
  const mimeType = file.type as 'image/jpeg' | 'image/png' | 'image/gif' | 'image/webp'

  try {
    const msg = await anthropic.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 300,
      messages: [{
        role: 'user',
        content: [
          {
            type: 'image',
            source: { type: 'base64', media_type: mimeType, data: base64 },
          },
          {
            type: 'text',
            text: `Extract financial information from this receipt or invoice. Return ONLY a JSON object with these fields (omit fields you can't determine):
{
  "title": "merchant name or description",
  "amount": number (total amount, positive),
  "date": "YYYY-MM-DD",
  "category": one of: utilities|maintenance|insurance|mortgage|renovation|cleaning|garden|security|appliances|other,
  "description": "brief description of what was purchased"
}
Return only valid JSON, no other text.`,
          },
        ],
      }],
    })

    const text = msg.content[0]?.type === 'text' ? msg.content[0].text.trim() : ''
    // Extract JSON from the response
    const match = text.match(/\{[\s\S]*\}/)
    if (!match) return NextResponse.json({ error: 'Could not parse receipt' }, { status: 422 })
    const parsed = JSON.parse(match[0]) as {
      title?: string; amount?: number; date?: string; category?: string; description?: string
    }
    return NextResponse.json({ result: parsed })
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'OCR failed'
    return NextResponse.json({ error: msg }, { status: 500 })
  }
}
