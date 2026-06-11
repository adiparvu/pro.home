import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'

export async function GET(req: NextRequest) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const property = await getActiveProperty(supabase, user.id)
  if (!property) return NextResponse.json({ error: 'No active property' }, { status: 400 })

  const { searchParams } = new URL(req.url)
  const year = searchParams.get('year') ?? String(new Date().getFullYear())
  const yearStart = `${year}-01-01`
  const yearEnd = `${year}-12-31`

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: records } = await (supabase as any)
    .from('financial_records')
    .select('type, category, amount, currency, date, title')
    .eq('property_id', property.id)
    .gte('date', yearStart)
    .lte('date', yearEnd)
    .order('date', { ascending: false })
    .limit(2000) as {
      data: Array<{
        type: string
        category: string
        amount: number
        currency: string
        date: string
        title: string
      }> | null
    }

  const allRecords = records ?? []

  const expenses = allRecords.filter((r) => r.type === 'expense')
  const incomeRecords = allRecords.filter((r) => r.type === 'income')

  const totalExpenses = expenses.reduce((s, r) => s + r.amount, 0)
  const totalIncome = incomeRecords.reduce((s, r) => s + r.amount, 0)
  const netResult = totalIncome - totalExpenses

  // Group expenses by category
  const byCategory: Record<string, number> = {}
  for (const r of expenses) {
    byCategory[r.category] = (byCategory[r.category] ?? 0) + r.amount
  }

  const categoryRows = Object.entries(byCategory)
    .sort(([, a], [, b]) => b - a)
    .map(([cat, total]) => {
      const pct = totalExpenses > 0 ? ((total / totalExpenses) * 100).toFixed(1) : '0.0'
      return `<tr>
        <td class="cap">${cat}</td>
        <td class="num">€${total.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td>
        <td class="num">${pct}%</td>
      </tr>`
    })
    .join('')

  const now = new Date()
  const generatedDate = now.toLocaleDateString('en', { year: 'numeric', month: 'long', day: 'numeric' })

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Tax Summary Report — ${property.name} — ${year}</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, -apple-system, sans-serif; font-size: 13px; color: #1a1a2e; line-height: 1.6; padding: 40px; background: #fff; max-width: 800px; margin: 0 auto; }
  h1 { font-size: 24px; font-weight: 700; margin-bottom: 4px; }
  h2 { font-size: 16px; font-weight: 600; margin: 28px 0 10px; border-bottom: 2px solid #e5e7eb; padding-bottom: 6px; color: #111827; }
  .subtitle { color: #6b7280; font-size: 12px; margin-bottom: 32px; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 12px; }
  th { text-align: left; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; color: #6b7280; padding: 8px 12px; border-bottom: 1px solid #e5e7eb; background: #f9fafb; }
  td { padding: 8px 12px; border-bottom: 1px solid #f3f4f6; }
  tr:last-child td { border-bottom: none; }
  .num { text-align: right; font-variant-numeric: tabular-nums; font-weight: 500; }
  .cap { text-transform: capitalize; }
  .summary-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin: 16px 0; }
  .kpi { background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 10px; padding: 16px; }
  .kpi-label { font-size: 11px; color: #6b7280; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 6px; }
  .kpi-value { font-size: 22px; font-weight: 700; color: #111827; }
  .kpi-value.green { color: #16a34a; }
  .kpi-value.red { color: #dc2626; }
  .footer { margin-top: 40px; padding-top: 16px; border-top: 1px solid #e5e7eb; font-size: 11px; color: #9ca3af; display: flex; justify-content: space-between; }
  @media print { body { padding: 20px; } }
</style>
</head>
<body>
<h1>Tax Summary Report</h1>
<p class="subtitle">${property.name} &mdash; Tax Year ${year} &mdash; ${property.address_line1 ? property.address_line1 + ', ' : ''}${property.city ?? ''}${property.country ? ', ' + property.country : ''}</p>

<h2>Financial Summary</h2>
<div class="summary-grid">
  <div class="kpi">
    <div class="kpi-label">Total Income</div>
    <div class="kpi-value green">€${totalIncome.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</div>
  </div>
  <div class="kpi">
    <div class="kpi-label">Total Expenses</div>
    <div class="kpi-value red">€${totalExpenses.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</div>
  </div>
  <div class="kpi">
    <div class="kpi-label">Net Result</div>
    <div class="kpi-value ${netResult >= 0 ? 'green' : 'red'}">€${netResult.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</div>
  </div>
</div>

<h2>Expenses by Category</h2>
${categoryRows.length === 0
    ? '<p style="color:#6b7280;font-size:12px">No expenses recorded for this year.</p>'
    : `<table>
  <thead><tr><th>Category</th><th style="text-align:right">Total Expenses</th><th style="text-align:right">% of Total</th></tr></thead>
  <tbody>${categoryRows}</tbody>
  <tfoot>
    <tr style="font-weight:700;background:#f9fafb">
      <td>Total</td>
      <td class="num">€${totalExpenses.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td>
      <td class="num">100%</td>
    </tr>
  </tfoot>
</table>`}

<h2>Income Summary</h2>
<p style="font-size:12px;color:#374151">Total income for ${year}: <strong>€${totalIncome.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong></p>

<h2>Net Result</h2>
<p style="font-size:12px;color:#374151">
  Income (€${totalIncome.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}) &minus;
  Expenses (€${totalExpenses.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}) =
  <strong style="color:${netResult >= 0 ? '#16a34a' : '#dc2626'}">€${netResult.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong>
  ${netResult >= 0 ? '(surplus)' : '(deficit)'}
</p>

<div class="footer">
  <span>Generated by PRV House on ${generatedDate}</span>
  <span>${property.name} &mdash; Tax Year ${year}</span>
</div>
</body>
</html>`

  return new NextResponse(html, {
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Disposition': `attachment; filename="tax-report-${year}.html"`,
    },
  })
}
