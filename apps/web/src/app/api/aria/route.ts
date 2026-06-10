import { NextRequest, NextResponse } from 'next/server'
import * as Sentry from '@sentry/nextjs'
import Anthropic from '@anthropic-ai/sdk'
import { createClient } from '@/lib/supabase/server'
import { checkRateLimit } from '@/lib/rate-limit'
import type { Property, InventoryItem, MaintenanceTask, EnergyReading, SecurityEvent, FinancialRecord, GardenPlant, GardenTask, Document } from '@/lib/supabase/types'

const BASE_SYSTEM_PROMPT = `You are ARIA (Adaptive Residence Intelligence Assistant), an AI property brain for PRV HOUSE — a smart home management app.

You help homeowners with:
- Maintenance planning and scheduling (seasonal checklists, appliance care, when to service systems)
- Energy optimization (reducing bills, improving efficiency, understanding usage patterns)
- Security advice (best practices, device recommendations, vulnerability checks)
- Cost estimation (repair budgets, material costs, contractor guidance)
- General home improvement and property questions

Guidelines:
- Be concise and practical. Give actionable advice, not generic platitudes.
- When giving lists, keep them short (3-5 items max unless asked for more).
- Use the user's property context when available — reference specific items and tasks they have.
- If you don't know something specific to their home, say so and give general guidance.
- Respond in the same language the user writes in.
- Format responses with **bold** for key terms and use bullet points (•) for lists.
- For cost estimates, give realistic ranges and note when a professional assessment is needed.`

type SlimSecurity = { mode: string } | null

function buildContextBlock(
  property: Property | null,
  items: InventoryItem[],
  tasks: MaintenanceTask[],
  energyReadings: EnergyReading[],
  securityState: SlimSecurity,
  unresolvedEvents: Pick<SecurityEvent, 'event_type' | 'severity' | 'description'>[],
  financialRecords: Pick<FinancialRecord, 'amount' | 'type' | 'category' | 'date'>[],
  gardenPlants: Pick<GardenPlant, 'name' | 'status' | 'next_watering'>[],
  gardenTasks: Pick<GardenTask, 'title' | 'status' | 'due_date'>[],
  expiringDocs: Pick<Document, 'name' | 'category' | 'expires_at'>[],
): string {
  if (!property) return ''

  const lines: string[] = [
    '\n\n--- PROPERTY CONTEXT ---',
    `Property: ${property.name}`,
    `Type: ${property.property_type ?? 'unknown'}`,
    `Size: ${property.size_sqm ? `${property.size_sqm} m²` : 'unknown'}`,
    `Year built: ${property.year_built ?? 'unknown'}`,
    `Location: ${[property.city, property.country].filter(Boolean).join(', ') || 'unknown'}`,
    `Health score: ${property.health_score ?? 'not computed'}`,
  ]

  if (items.length > 0) {
    lines.push(`\nInventory (${items.length} items):`)
    items.slice(0, 20).forEach((item) => {
      const parts = [item.name]
      if (item.brand) parts.push(item.brand)
      if (item.condition) parts.push(`(${item.condition})`)
      if (item.warranty_expires) parts.push(`warranty until ${item.warranty_expires}`)
      if (item.recall_active) parts.push('[RECALL ACTIVE]')
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
      if (task.is_recurring) parts.push('[recurring]')
      lines.push(`  • ${parts.join(' ')}`)
    })
  }

  if (energyReadings.length > 0) {
    const latestByType = new Map<string, EnergyReading>()
    for (const r of energyReadings) {
      if (!latestByType.has(r.meter_type)) latestByType.set(r.meter_type, r)
    }
    lines.push('\nLatest energy readings:')
    for (const r of latestByType.values()) {
      const costStr = r.cost != null ? ` · ${r.cost_currency ?? 'EUR'} ${r.cost}` : ''
      lines.push(`  • ${r.meter_type}: ${r.reading_value} ${r.unit}${costStr} (${r.reading_date})`)
    }
  }

  if (financialRecords.length > 0) {
    const thisYear = new Date().getFullYear().toString()
    const ytdExpenses = financialRecords
      .filter((r) => r.type === 'expense' && r.date.startsWith(thisYear))
      .reduce((s, r) => s + r.amount, 0)
    const ytdIncome = financialRecords
      .filter((r) => r.type === 'income' && r.date.startsWith(thisYear))
      .reduce((s, r) => s + r.amount, 0)
    // Category breakdown
    const catTotals: Record<string, number> = {}
    for (const r of financialRecords.filter((r) => r.type === 'expense')) {
      catTotals[r.category] = (catTotals[r.category] ?? 0) + r.amount
    }
    const topCats = Object.entries(catTotals).sort((a, b) => b[1] - a[1]).slice(0, 3)
    lines.push(`\nFinances (YTD): expenses €${ytdExpenses.toFixed(0)}, income €${ytdIncome.toFixed(0)}, net €${(ytdIncome - ytdExpenses).toFixed(0)}`)
    if (topCats.length > 0) {
      lines.push(`Top expense categories: ${topCats.map(([c, a]) => `${c} €${a.toFixed(0)}`).join(', ')}`)
    }
  }

  if (gardenPlants.length > 0) {
    const today = new Date().toISOString().split('T')[0]!
    const needsWater = gardenPlants.filter((p) => p.next_watering && p.next_watering <= today)
    lines.push(`\nGarden: ${gardenPlants.length} plants`)
    if (needsWater.length > 0) lines.push(`  • ${needsWater.length} plant${needsWater.length !== 1 ? 's' : ''} need watering`)
    gardenPlants.filter((p) => p.status === 'needs_attention').slice(0, 3).forEach((p) => lines.push(`  • ${p.name} [needs attention]`))
  }

  if (gardenTasks.filter((t) => t.status !== 'done').length > 0) {
    const openGarden = gardenTasks.filter((t) => t.status !== 'done')
    lines.push(`Garden tasks pending: ${openGarden.length}`)
    openGarden.slice(0, 5).forEach((t) => {
      const due = t.due_date ? ` (due ${t.due_date})` : ''
      lines.push(`  • ${t.title}${due}`)
    })
  }

  if (expiringDocs.length > 0) {
    lines.push(`\nDocuments expiring within 30 days:`)
    expiringDocs.forEach((d) => {
      const exp = d.expires_at ? new Date(d.expires_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : ''
      lines.push(`  • ${d.name} [${d.category}] expires ${exp}`)
    })
  }

  if (securityState) {
    lines.push(`\nSecurity mode: ${securityState.mode}`)
  }

  if (unresolvedEvents.length > 0) {
    lines.push(`Unresolved security events (${unresolvedEvents.length}):`)
    unresolvedEvents.slice(0, 3).forEach((e) => {
      const desc = e.description ? `: ${e.description}` : ''
      lines.push(`  • ${e.event_type} [${e.severity}]${desc}`)
    })
  }

  lines.push('--- END CONTEXT ---')
  return lines.join('\n')
}

const RATE_LIMIT_PER_MINUTE = 20
const MAX_MESSAGES = 50
const MAX_MESSAGE_LENGTH = 4000
const MAX_MESSAGES_PER_REQUEST = 20

export async function POST(req: NextRequest) {
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

  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

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

  let body: { messages: { role: string; content: string }[] }
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const { messages } = body
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
      return NextResponse.json({ error: `Message content must not exceed ${MAX_MESSAGE_LENGTH} characters` }, { status: 400 })
    }
  }

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
  let energyReadings: EnergyReading[] = []
  let securityState: SlimSecurity = null
  let unresolvedEvents: Pick<SecurityEvent, 'event_type' | 'severity' | 'description'>[] = []
  let financialRecords: Pick<FinancialRecord, 'amount' | 'type' | 'category' | 'date'>[] = []
  let gardenPlants: Pick<GardenPlant, 'name' | 'status' | 'next_watering'>[] = []
  let gardenTasks: Pick<GardenTask, 'title' | 'status' | 'due_date'>[] = []
  let expiringDocs: Pick<Document, 'name' | 'category' | 'expires_at'>[] = []

  if (property) {
    const sb = supabase as any // eslint-disable-line @typescript-eslint/no-explicit-any
    const [itemsRes, tasksRes, energyRes, secStateRes, secEventsRes, finRes, plantsRes, gTasksRes, docsRes] = await Promise.all([
      supabase.from('inventory_items').select('*').eq('property_id', property.id).limit(50),
      supabase.from('maintenance_tasks').select('*').eq('property_id', property.id).neq('status', 'cancelled').limit(50),
      sb.from('energy_readings').select('*').eq('property_id', property.id).order('reading_date', { ascending: false }).limit(12) as Promise<{ data: EnergyReading[] | null }>,
      sb.from('security_state').select('mode').eq('property_id', property.id).maybeSingle() as Promise<{ data: { mode: string } | null }>,
      sb.from('security_events').select('event_type, severity, description').eq('property_id', property.id).is('resolved_at', null).order('created_at', { ascending: false }).limit(5) as Promise<{ data: Pick<SecurityEvent, 'event_type' | 'severity' | 'description'>[] | null }>,
      sb.from('financial_records').select('amount, type, category, date').eq('property_id', property.id).order('date', { ascending: false }).limit(100) as Promise<{ data: Pick<FinancialRecord, 'amount' | 'type' | 'category' | 'date'>[] | null }>,
      sb.from('garden_plants').select('name, status, next_watering').eq('property_id', property.id).limit(30) as Promise<{ data: Pick<GardenPlant, 'name' | 'status' | 'next_watering'>[] | null }>,
      sb.from('garden_tasks').select('title, status, due_date').eq('property_id', property.id).neq('status', 'completed').limit(20) as Promise<{ data: Pick<GardenTask, 'title' | 'status' | 'due_date'>[] | null }>,
      supabase.from('documents').select('name, category, expires_at').eq('property_id', property.id).not('expires_at', 'is', null).lte('expires_at', new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()).gt('expires_at', new Date().toISOString()).limit(5) as unknown as Promise<{ data: Pick<Document, 'name' | 'category' | 'expires_at'>[] | null }>,
    ])
    items = (itemsRes.data ?? []) as InventoryItem[]
    tasks = (tasksRes.data ?? []) as MaintenanceTask[]
    energyReadings = energyRes.data ?? []
    securityState = secStateRes.data
    unresolvedEvents = secEventsRes.data ?? []
    financialRecords = finRes.data ?? []
    gardenPlants = plantsRes.data ?? []
    gardenTasks = gTasksRes.data ?? []
    expiringDocs = docsRes.data ?? []
  }

  const systemPrompt = BASE_SYSTEM_PROMPT + buildContextBlock(
    property, items, tasks, energyReadings, securityState, unresolvedEvents,
    financialRecords, gardenPlants, gardenTasks, expiringDocs,
  )

  const recentMessages = messages.slice(-MAX_MESSAGES_PER_REQUEST).map((m) => ({
    role: m.role as 'user' | 'assistant',
    content: m.content,
  }))

  const client = new Anthropic({ apiKey })

  try {
    const stream = client.messages.stream({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 2048,
      system: systemPrompt,
      messages: recentMessages,
    })

    const encoder = new TextEncoder()
    const readable = new ReadableStream({
      async start(controller) {
        try {
          stream.on('text', (text) => {
            controller.enqueue(encoder.encode(text))
          })
          await stream.finalMessage()
        } catch (err) {
          Sentry.captureException(err, { tags: { route: '/api/aria' } })
        } finally {
          controller.close()
        }
      },
      cancel() {
        stream.abort()
      },
    })

    return new Response(readable, {
      headers: {
        'Content-Type': 'text/plain; charset=utf-8',
        'X-Content-Type-Options': 'nosniff',
        'X-RateLimit-Limit': String(RATE_LIMIT_PER_MINUTE),
        'X-RateLimit-Remaining': String(rl.remaining),
      },
    })
  } catch (err) {
    Sentry.captureException(err, { tags: { route: '/api/aria' } })
    console.error('ARIA API error:', err)
    return NextResponse.json({ error: 'ARIA encountered an error. Please try again.' }, { status: 500 })
  }
}
