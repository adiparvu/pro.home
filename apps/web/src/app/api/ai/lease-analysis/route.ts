import { NextRequest, NextResponse } from 'next/server'
import Anthropic from '@anthropic-ai/sdk'
import { createClient } from '@/lib/supabase/server'

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY ?? '' })

export async function POST(req: NextRequest) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const body = await req.json() as { lease_id?: string; lease_text?: string }
  if (!body.lease_text?.trim()) {
    return NextResponse.json({ error: 'lease_text is required' }, { status: 400 })
  }

  try {
    const msg = await anthropic.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 1200,
      messages: [{
        role: 'user',
        content: `Analyze this lease agreement and extract:
1. Key obligations for tenant and landlord
2. Red flags or unusual clauses (list each)
3. Important dates (renewal notice deadline, break clause, etc.)
4. Rent escalation terms
5. Deposit return conditions

Respond with JSON only:
{ "obligations": string[], "redFlags": string[], "importantDates": string[], "rentEscalation": string, "depositConditions": string, "summary": string }

Lease text:
${body.lease_text.substring(0, 8000)}`,
      }],
    })

    const text = msg.content[0]?.type === 'text' ? msg.content[0].text.trim() : ''
    const match = text.match(/\{[\s\S]*\}/)
    if (!match) return NextResponse.json({ error: 'Could not parse AI response' }, { status: 422 })

    const parsed = JSON.parse(match[0]) as {
      obligations: string[]
      redFlags: string[]
      importantDates: string[]
      rentEscalation: string
      depositConditions: string
      summary: string
    }

    return NextResponse.json(parsed)
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Analysis failed'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
