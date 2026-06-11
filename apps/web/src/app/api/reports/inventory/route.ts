import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'

export async function GET() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const property = await getActiveProperty(supabase, user.id)
  if (!property) return NextResponse.json({ error: 'No active property' }, { status: 400 })

  const { data: items } = await supabase
    .from('inventory_items')
    .select('*')
    .eq('property_id', property.id)
    .order('category')
    .order('name') as { data: Array<{
      id: string; name: string; brand: string | null; model: string | null; category: string | null
      condition: string | null; serial_number: string | null; purchase_year: number | null
      purchase_price: number | null; current_value: number | null; warranty_expires: string | null
      location: string | null; notes: string | null; manual_url: string | null
    }> | null }

  const now = new Date()
  const itemList = items ?? []

  const grouped: Record<string, typeof itemList> = {}
  for (const item of itemList) {
    const cat = item.category ?? 'other'
    if (!grouped[cat]) grouped[cat] = []
    grouped[cat].push(item)
  }

  const totalValue = itemList.reduce((s, i) => s + (i.current_value ?? i.purchase_price ?? 0), 0)

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Inventory Report — ${property.name}</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; font-size: 12px; color: #1a1a2e; line-height: 1.5; padding: 32px; }
  h1 { font-size: 20px; font-weight: 700; margin-bottom: 4px; }
  h2 { font-size: 13px; font-weight: 700; margin: 20px 0 8px; text-transform: uppercase; letter-spacing: 0.06em; color: #6b7280; border-bottom: 1px solid #e5e7eb; padding-bottom: 4px; }
  .meta { color: #6b7280; font-size: 11px; margin-bottom: 20px; }
  .summary { display: grid; grid-template-columns: repeat(3,1fr); gap: 12px; margin-bottom: 24px; }
  .kpi { background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 8px; padding: 10px 12px; }
  .kpi-label { font-size: 10px; color: #6b7280; text-transform: uppercase; }
  .kpi-value { font-size: 16px; font-weight: 700; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 4px; page-break-inside: avoid; }
  th { text-align: left; font-size: 10px; text-transform: uppercase; color: #6b7280; padding: 5px 6px; border-bottom: 1px solid #e5e7eb; }
  td { padding: 5px 6px; border-bottom: 1px solid #f3f4f6; vertical-align: top; }
  tr:last-child td { border-bottom: none; }
  .cond { display: inline-block; padding: 1px 6px; border-radius: 9999px; font-size: 10px; font-weight: 600; }
  .cond-good { background: #f0fdf4; color: #16a34a; }
  .cond-fair { background: #fffbeb; color: #d97706; }
  .cond-poor { background: #fef2f2; color: #dc2626; }
  .footer { margin-top: 32px; border-top: 1px solid #e5e7eb; padding-top: 12px; font-size: 10px; color: #9ca3af; display: flex; justify-content: space-between; }
  @media print { body { padding: 16px; } }
</style>
</head>
<body>
<h1>Inventory Report — ${property.name}</h1>
<p class="meta">Generated ${now.toLocaleDateString('en', { year:'numeric',month:'long',day:'numeric' })}</p>

<div class="summary">
  <div class="kpi"><div class="kpi-label">Total items</div><div class="kpi-value">${itemList.length}</div></div>
  <div class="kpi"><div class="kpi-label">Est. total value</div><div class="kpi-value">€${totalValue.toFixed(0)}</div></div>
  <div class="kpi"><div class="kpi-label">Needs attention</div><div class="kpi-value">${itemList.filter(i => i.condition === 'poor' || i.condition === 'broken').length}</div></div>
</div>

${Object.entries(grouped).map(([cat, catItems]) => `
<h2>${cat} (${catItems.length})</h2>
<table>
  <thead><tr>
    <th>Item</th><th>Brand / Model</th><th>Condition</th><th>Year</th><th>Value</th><th>Warranty</th><th>Serial</th>
  </tr></thead>
  <tbody>
    ${catItems.map((i) => `<tr>
      <td>${i.name}${i.location ? `<br><span style="font-size:10px;color:#9ca3af">${i.location}</span>` : ''}</td>
      <td>${[i.brand, i.model].filter(Boolean).join(' ') || '—'}</td>
      <td><span class="cond ${i.condition === 'excellent' || i.condition === 'good' ? 'cond-good' : i.condition === 'fair' ? 'cond-fair' : i.condition === 'poor' || i.condition === 'broken' ? 'cond-poor' : ''}">${i.condition ?? '—'}</span></td>
      <td>${i.purchase_year ?? '—'}</td>
      <td>${i.current_value != null ? '€' + i.current_value.toFixed(0) : i.purchase_price != null ? '€' + i.purchase_price.toFixed(0) : '—'}</td>
      <td>${i.warranty_expires ?? '—'}</td>
      <td style="font-size:10px;font-family:monospace">${i.serial_number ?? '—'}</td>
    </tr>`).join('')}
  </tbody>
</table>`).join('')}

<div class="footer">
  <span>PRV HOUSE · ${property.name}</span>
  <span>${now.toISOString()}</span>
</div>
</body>
</html>`

  return new NextResponse(html, {
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Disposition': `inline; filename="inventory-${property.id.slice(0,8)}-${now.toISOString().split('T')[0]}.html"`,
    },
  })
}
