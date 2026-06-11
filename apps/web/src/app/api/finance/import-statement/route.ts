import { NextRequest, NextResponse } from 'next/server'
import Anthropic from '@anthropic-ai/sdk'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY ?? '' })

export interface ParsedTransaction {
  date: string
  description: string
  amount: number
  category: string
}

export async function POST(req: NextRequest) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const property = await getActiveProperty(supabase, user.id)
  if (!property) return NextResponse.json({ error: 'No active property' }, { status: 404 })

  const form = await req.formData()
  const file = form.get('file') as File | null
  const currency = (form.get('currency') as string | null) ?? 'EUR'

  if (!file) return NextResponse.json({ error: 'No file provided' }, { status: 400 })
  if (file.size > 2 * 1024 * 1024) return NextResponse.json({ error: 'File too large (max 2 MB)' }, { status: 400 })

  const fileContent = await file.text()

  try {
    const msg = await anthropic.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 2000,
      messages: [{
        role: 'user',
        content: `Parse this bank statement CSV/text and extract transactions. For each transaction return:
{ "date": "YYYY-MM-DD", "description": string, "amount": number (positive=credit, negative=debit), "category": string (one of: maintenance/utilities/groceries/services/renovation/insurance/mortgage/tax/other) }
Return JSON array only. Skip balance rows, opening/closing balance, bank fees under 1 EUR.
Maximum 50 transactions.

Statement:
${fileContent.substring(0, 6000)}`,
      }],
    })

    const text = msg.content[0]?.type === 'text' ? msg.content[0].text.trim() : ''
    const match = text.match(/\[[\s\S]*\]/)
    if (!match) return NextResponse.json({ error: 'Could not parse statement' }, { status: 422 })

    const transactions = JSON.parse(match[0]) as ParsedTransaction[]

    // Return parsed preview — actual insert is done via the "preview" flag
    const shouldInsert = form.get('insert') === 'true'
    if (!shouldInsert) {
      return NextResponse.json({ records: transactions })
    }

    // Insert debit transactions (amount < 0) as expenses
    const debits = transactions.filter((t) => t.amount < 0)
    let imported = 0
    const skipped = transactions.length - debits.length

    if (debits.length > 0) {
      const rows = debits.map((t) => ({
        property_id: property.id,
        created_by: user.id,
        title: t.description,
        amount: Math.abs(t.amount),
        currency,
        type: 'expense',
        category: t.category,
        date: t.date,
        tags: [],
        is_recurring: false,
      }))

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { error } = await (supabase as any)
        .from('financial_records')
        .insert(rows)

      if (error) throw error
      imported = debits.length
    }

    return NextResponse.json({ imported, skipped, records: transactions })
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Import failed'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
