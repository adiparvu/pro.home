import { NextRequest, NextResponse } from 'next/server'
import * as Sentry from '@sentry/nextjs'
import Anthropic from '@anthropic-ai/sdk'
import { createClient } from '@/lib/supabase/server'
import { checkRateLimit } from '@/lib/rate-limit'
import type { Property, InventoryItem, MaintenanceTask } from '@/lib/supabase/types'

const BASE_SYSTEM_PROMPT = `You are ARIA (Adaptive Residence Intelligence Assistant), an AI property brain for PRV HOUSE — a smart home management app.

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

function buildContextBlock(
  property: Property | null,
  items: InventoryItem[],
  tasks: MaintenanceTask[],
): string {
  if (!property) return ''

  const lines: string[] = [
    '\n\n--- PROPERTY CONTEXT ---',
    `Property: ${property.name}`,
    `Type: ${property.property_type ?? 'unknown'}`,
    `Size: ${property.size_sqm ? `${property.size_sqm} m²` : 'unknown'}`,
    `Year built: ${property.year_built ?? 'unknown'}`,
    `Location: ${[property.city, property.country].filter(Boolean).join(', ') || 'unknown'}`,
  ]

  if (items.length > 0) {
    lines.push(`\nInventory (${items.length} items):`)
    items.slice(0, 20).forEach((item) => {
      const parts = [item.name]
      if (item.brand) parts.push(item.brand)
      if (item.condition) parts.push(`(${item.condition})`)
      if (item.warranty_expires) parts.push(`warranty until ${item.warranty_expires}`)
      lines.push(`  • ${parts.join(' ')}`)
    })
    if (items.length > 20) lines.push(`  … and ${items.length - 20} more`)
  }

  const openTasks = tasks.filter((t) => t.status !== 'completed' && t.status !== 'cancelled')
  if (openTasks.length > 0) {
    lines.push(`\nOpen maintenance tasks (${openTasks.length}):`)
    openTasks.slice(0, 10).forEach((task) => {
      const parts = [task.title]
      if (task.status === 'overdue') parts.push('[OVERDUE]')
      if (task.due_date) parts.push(`due ${task.due_date}`)
      lines.push(`  • ${parts.join(' ')}`)
    })
  }

  lines.push('--- END CONTEXT ---')
  return lines.join('\n')
}

// Constants
const RATE_LIMIT_PER_MINUTE = 20
const MAX_MESSAGES = 50
const MAX_MESSAGE_LENGTH = 4000
const MAX_MESSAGES_PER_REQUEST = 20

export async function POST(req: NextRequest) {
  // Enforce JSON content type
  const contentType = req.headers.get('content-type') ?? ''
  if (!contentType.includes('application/json')) {
    return NextResponse.json({ error: 'Content-Type must be application/json' }, { status: 415 })
  }

  const apiKey = process.env.ANTHROPIC_API_KEY
  if (!apiKey) {
    return NextResponse.json(
      { error: 'ARIA is not yet configured. Add ANTHROPIC_API_KEY to your environment.' },
      { status: 503 },
    )
  }

  // Auth check
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  // Per-user rate limiting: 20 requests/minute
  const rl = checkRateLimit(`aria:${user.id}`, RATE_LIMIT_PER_MINUTE, 60)
  if (!rl.allowed) {
    return NextResponse.json(
      { error: `Too many requests. Please wait ${rl.retryAfter}s before trying again.` },
      {
        status: 429,
        headers: {
          'Retry-After': String(rl.retryAfter),
          'X-RateLimit-Limit': String(RATE_LIMIT_PER_MINUTE),
          'X-RateLimit-Remaining': '0',
        },
      },
    )
  }

  // Parse body
  let body: { messages: { role: string; content: string }[] }
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const { messages } = body

  // Validate messages array
  if (!Array.isArray(messages) || messages.length === 0) {
    return NextResponse.json({ error: 'messages array is required and must not be empty' }, { status: 400 })
  }
  if (messages.length > MAX_MESSAGES) {
    return NextResponse.json({ error: `messages array must not exceed ${MAX_MESSAGES} items` }, { status: 400 })
  }
  for (const msg of messages) {
    if (!msg || typeof msg.role !== 'string' || typeof msg.content !== 'string') {
      return NextResponse.json({ error: 'Each message must have role (string) and content (string)' }, { status: 400 })
    }
    if (!['user', 'assistant'].includes(msg.role)) {
      return NextResponse.json({ error: 'Message role must be "user" or "assistant"' }, { status: 400 })
    }
    if (msg.content.length > MAX_MESSAGE_LENGTH) {
      return NextResponse.json(
        { error: `Message content must not exceed ${MAX_MESSAGE_LENGTH} characters` },
        { status: 400 },
      )
    }
  }

  // Fetch property context
  const { data: property } = await supabase
    .from('properties')
    .select('*, property_members!inner(status)')
    .eq('property_members.user_id', user.id)
    .eq('property_members.status', 'active')
    .eq('is_active', true)
    .order('created_at', { ascending: false })
    .limit(1)
    .single() as { data: Property | null; error: unknown }

  let items: InventoryItem[] = []
  let tasks: MaintenanceTask[] = []

  if (property) {
    const [itemsRes, tasksRes] = await Promise.all([
      supabase.from('inventory_items').select('*').eq('property_id', property.id).limit(50),
      supabase.from('maintenance_tasks').select('*').eq('property_id', property.id).neq('status', 'cancelled').limit(50),
    ])
    items = (itemsRes.data ?? []) as InventoryItem[]
    tasks = (tasksRes.data ?? []) as MaintenanceTask[]
  }

  const systemPrompt = BASE_SYSTEM_PROMPT + buildContextBlock(property, items, tasks)

  const recentMessages = messages.slice(-MAX_MESSAGES_PER_REQUEST).map((m) => ({
    role: m.role as 'user' | 'assistant',
    content: m.content,
  }))

  const client = new Anthropic({ apiKey })

  try {
    const response = await client.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 1024,
      system: systemPrompt,
      messages: recentMessages,
    })

    const text = response.content[0]?.type === 'text' ? response.content[0].text : ''
    return NextResponse.json(
      { content: text },
      {
        headers: {
          'X-RateLimit-Limit': String(RATE_LIMIT_PER_MINUTE),
          'X-RateLimit-Remaining': String(rl.remaining),
        },
      },
    )
  } catch (err) {
    Sentry.captureException(err, { tags: { route: '/api/aria' } })
    console.error('ARIA API error:', err)
    return NextResponse.json({ error: 'ARIA encountered an error. Please try again.' }, { status: 500 })
  }
}
