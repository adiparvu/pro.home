import { NextRequest, NextResponse } from 'next/server'
import Anthropic from '@anthropic-ai/sdk'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { checkRateLimit } from '@/lib/rate-limit'

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY ?? '' })

export async function POST(req: NextRequest) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { allowed } = checkRateLimit(`${user.id}:insights`, 5, 3600)
  const limited = !allowed
  if (limited) return NextResponse.json({ error: 'Rate limit reached. Please wait before refreshing insights.' }, { status: 429 })

  const property = await getActiveProperty(supabase, user.id)
  if (!property) return NextResponse.json({ error: 'No active property' }, { status: 400 })

  const now = new Date()
  const yearStart = `${now.getFullYear()}-01-01`
  const in90 = new Date(now.getTime() + 90 * 86400_000).toISOString().split('T')[0]!

  const [tasksRes, financesRes, inventoryRes, energyRes] = await Promise.all([
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('maintenance_tasks').select('title,status,priority,due_date,category,cost').eq('property_id', property.id).neq('status', 'cancelled').limit(50),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('financial_records').select('title,amount,type,category,date').eq('property_id', property.id).gte('date', yearStart).order('date', { ascending: false }).limit(80),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('inventory_items').select('name,brand,condition,warranty_expires,purchase_year').eq('property_id', property.id).limit(40),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('energy_readings').select('meter_type,value,reading_date,cost').eq('property_id', property.id).order('reading_date', { ascending: false }).limit(24),
  ])

  const tasks = tasksRes.data ?? []
  const finances = financesRes.data ?? []
  const inventory = inventoryRes.data ?? []
  const energy = energyRes.data ?? []

  const overdueTasks = tasks.filter((t: { status: string }) => t.status === 'overdue')
  const pendingTasks = tasks.filter((t: { status: string }) => t.status === 'pending' || t.status === 'in_progress')
  const ytdExpenses = finances.filter((f: { type: string }) => f.type === 'expense').reduce((s: number, f: { amount: number }) => s + f.amount, 0)
  const ytdIncome = finances.filter((f: { type: string }) => f.type === 'income').reduce((s: number, f: { amount: number }) => s + f.amount, 0)
  const expiringWarranties = inventory.filter((i: { warranty_expires: string | null }) => {
    if (!i.warranty_expires) return false
    return i.warranty_expires > now.toISOString().split('T')[0]! && i.warranty_expires < in90
  })

  const contextBlock = `
Property: ${property.name} (${property.property_type ?? 'unknown'}, ${property.size_sqm ? property.size_sqm + 'm²' : 'size unknown'}, built ${property.year_built ?? 'unknown'})
Health score: ${property.health_score ?? 'not computed'}/100
Today: ${now.toISOString().split('T')[0]}

TASKS (${tasks.length} total):
- Overdue: ${overdueTasks.length}
- Pending/in-progress: ${pendingTasks.length}
- Top overdue: ${overdueTasks.slice(0, 3).map((t: { title: string; priority: string }) => `${t.title} (${t.priority})`).join(', ') || 'none'}

FINANCES (YTD):
- Expenses: €${ytdExpenses.toFixed(0)}
- Income: €${ytdIncome.toFixed(0)}
- Net: €${(ytdIncome - ytdExpenses).toFixed(0)}
- Categories: ${
    Object.entries(
      finances.filter((f: { type: string }) => f.type === 'expense').reduce((acc: Record<string, number>, f: { category: string; amount: number }) => {
        acc[f.category] = (acc[f.category] ?? 0) + f.amount
        return acc
      }, {})
    ).sort(([, a], [, b]) => (b as number) - (a as number)).slice(0, 4).map(([k, v]) => `${k}: €${(v as number).toFixed(0)}`).join(', ')
  }

INVENTORY: ${inventory.length} items tracked
- Expiring warranties (90 days): ${expiringWarranties.map((i: { name: string; warranty_expires: string }) => `${i.name} (${i.warranty_expires})`).join(', ') || 'none'}
- Poor/broken items: ${inventory.filter((i: { condition: string | null }) => i.condition === 'poor' || i.condition === 'broken').map((i: { name: string }) => i.name).join(', ') || 'none'}

ENERGY: ${energy.length} readings
${energy.slice(0, 6).map((e: { meter_type: string; value: number; reading_date: string; cost: number | null }) => `  ${e.meter_type}: ${e.value} on ${e.reading_date}${e.cost ? ` (€${e.cost})` : ''}`).join('\n')}
`

  const { body } = req
  const { type } = body ? await req.json().catch(() => ({ type: 'full' })) : { type: 'full' }

  const prompt = type === 'anomalies'
    ? `Based on this property data, identify 2-3 specific financial anomalies or unusual spending patterns worth noting. Be concrete with numbers.\n\n${contextBlock}`
    : type === 'predictions'
    ? `Based on inventory ages and maintenance history, predict 3 maintenance items likely needed in the next 6 months. Give a rough cost estimate for each.\n\n${contextBlock}`
    : `Generate a concise property intelligence brief with exactly these 4 sections:

**Health Summary** (2 sentences: overall state, most urgent item)
**Financial Pulse** (2 sentences: spending trend, biggest category)
**Action Items** (3 bullet points: most important things to do this week)
**30-Day Forecast** (2 sentences: what to expect / prepare for)

Be specific, use the actual data provided. Keep each section tight.\n\n${contextBlock}`

  try {
    const message = await anthropic.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 600,
      messages: [{ role: 'user', content: prompt }],
    })
    const text = message.content[0]?.type === 'text' ? message.content[0].text : ''
    return NextResponse.json({ brief: text, generatedAt: now.toISOString() })
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'AI unavailable'
    return NextResponse.json({ error: msg }, { status: 500 })
  }
}
