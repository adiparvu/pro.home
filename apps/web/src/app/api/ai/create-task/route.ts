import { NextRequest, NextResponse } from 'next/server'
import Anthropic from '@anthropic-ai/sdk'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY ?? '' })

export async function POST(req: NextRequest) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const property = await getActiveProperty(supabase, user.id)
  if (!property) return NextResponse.json({ error: 'No active property' }, { status: 404 })

  const body = await req.json() as { text?: string }
  if (!body.text?.trim()) {
    return NextResponse.json({ error: 'text is required' }, { status: 400 })
  }

  const today = new Date().toISOString().split('T')[0]

  try {
    const msg = await anthropic.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 300,
      messages: [{
        role: 'user',
        content: `Extract a maintenance task from this text. Return JSON only:
{ "title": string, "description": string|null, "category": string (one of: maintenance/cleaning/inspection/utilities/garden/safety/other), "priority": string (low/medium/high/critical), "due_date": string|null (YYYY-MM-DD, relative dates like "next week" → calculate from today which is ${today}), "room": string|null }

Text: ${body.text.trim()}`,
      }],
    })

    const text = msg.content[0]?.type === 'text' ? msg.content[0].text.trim() : ''
    const match = text.match(/\{[\s\S]*\}/)
    if (!match) return NextResponse.json({ error: 'Could not parse task' }, { status: 422 })

    const parsed = JSON.parse(match[0]) as {
      title: string
      description: string | null
      category: string
      priority: string
      due_date: string | null
      room: string | null
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data, error } = await (supabase as any)
      .from('maintenance_tasks')
      .insert({
        property_id: property.id,
        created_by: user.id,
        title: parsed.title,
        description: parsed.description ?? null,
        category: parsed.category,
        priority: parsed.priority,
        due_date: parsed.due_date ?? null,
        room: parsed.room ?? null,
        status: 'pending',
      })
      .select('id, title, category, priority, due_date')
      .single()

    if (error) throw error

    return NextResponse.json({
      task_id: (data as { id: string }).id,
      title: (data as { title: string }).title,
      category: (data as { category: string }).category,
      priority: (data as { priority: string }).priority,
      due_date: (data as { due_date: string | null }).due_date,
    })
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Task creation failed'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
