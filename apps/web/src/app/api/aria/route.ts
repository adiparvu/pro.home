import { NextRequest, NextResponse } from 'next/server'
import Anthropic from '@anthropic-ai/sdk'
import { createClient } from '@/lib/supabase/server'

const SYSTEM_PROMPT = `You are ARIA (Adaptive Residence Intelligence Assistant), an AI property brain for PRV HOUSE — a smart home management app.

You help homeowners with:
- Maintenance planning and scheduling (seasonal checklists, appliance care, when to service systems)
- Energy optimization (reducing bills, improving efficiency, understanding usage)
- Security advice (best practices, device recommendations, vulnerability checks)
- Cost estimation (repair budgets, material costs, contractor guidance)
- General home improvement and property questions

Guidelines:
- Be concise and practical. Give actionable advice, not generic platitudes.
- When giving lists, keep them short (3-5 items max unless asked for more).
- Use the user's property context when available.
- If you don't know something specific to their home, say so and give general guidance.
- Respond in the same language the user writes in.
- Format responses with **bold** for key terms and use bullet points (•) for lists.`

export async function POST(req: NextRequest) {
  const apiKey = process.env.ANTHROPIC_API_KEY
  if (!apiKey) {
    return NextResponse.json(
      { error: 'ARIA is not yet configured. Add ANTHROPIC_API_KEY to your environment.' },
      { status: 503 }
    )
  }

  // Auth check
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  let body: { messages: { role: string; content: string }[] }
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'Invalid request body' }, { status: 400 })
  }

  const { messages } = body
  if (!Array.isArray(messages) || messages.length === 0) {
    return NextResponse.json({ error: 'messages array required' }, { status: 400 })
  }

  // Last 20 messages for context (keep costs low)
  const recentMessages = messages.slice(-20).map((m) => ({
    role: m.role as 'user' | 'assistant',
    content: String(m.content),
  }))

  const client = new Anthropic({ apiKey })

  try {
    const response = await client.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 1024,
      system: SYSTEM_PROMPT,
      messages: recentMessages,
    })

    const text = response.content[0]?.type === 'text' ? response.content[0].text : ''
    return NextResponse.json({ content: text })
  } catch (err) {
    console.error('ARIA API error:', err)
    return NextResponse.json({ error: 'ARIA encountered an error. Please try again.' }, { status: 500 })
  }
}
