import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'

function esc(s: string | null | undefined): string {
  if (!s) return ''
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

function fmtDate(d: string | null | undefined): string {
  if (!d) return '—'
  return new Date(d).toLocaleDateString('en', { day: 'numeric', month: 'short', year: 'numeric' })
}

function fmtMoney(v: number | null | undefined, currency: string | null | undefined): string {
  if (v == null) return '—'
  const cur = currency ?? 'EUR'
  return `${cur} ${v.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

export async function GET() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const property = await getActiveProperty(supabase, user.id)
  if (!property) return NextResponse.json({ error: 'No active property' }, { status: 400 })

  const { data: items } = await supabase
    .from('inventory_items')
    .select('id, name, brand, model, serial_number, category, condition, purchase_date, purchase_price, purchase_currency, current_value, warranty_expires, photo_urls')
    .eq('property_id', property.id)
    .order('category')
    .order('name') as {
      data: Array<{
        id: string
        name: string
        brand: string | null
        model: string | null
        serial_number: string | null
        category: string | null
        condition: string | null
        purchase_date: string | null
        purchase_price: number | null
        purchase_currency: string | null
        current_value: number | null
        warranty_expires: string | null
        photo_urls: string[] | null
      }> | null
    }

  const now = new Date()
  const itemList = items ?? []

  const totalDeclaredValue = itemList.reduce((sum, item) => {
    return sum + (item.current_value ?? item.purchase_price ?? 0)
  }, 0)

  const currency = property.currency ?? 'EUR'

  const tableRows = itemList.map((item) => {
    const brandModel = [item.brand, item.model].filter(Boolean).join(' / ')
    const declaredValue = item.current_value ?? item.purchase_price
    return `<tr>
      <td>${esc(item.name)}</td>
      <td>${esc(brandModel) || '—'}</td>
      <td style="font-family:monospace;font-size:11px">${esc(item.serial_number) || '—'}</td>
      <td class="cap">${esc(item.category) || '—'}</td>
      <td class="cap">${esc(item.condition) || '—'}</td>
      <td>${fmtDate(item.purchase_date)}</td>
      <td class="mono">${declaredValue != null ? fmtMoney(declaredValue, item.purchase_currency ?? currency) : '—'}</td>
    </tr>`
  }).join('\n')

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Insurance Claim — ${esc(property.name)}</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; font-size: 12px; color: #0D1420; line-height: 1.5; background: #fff; padding: 32px; }
  header { border-bottom: 2px solid #0D1420; padding-bottom: 16px; margin-bottom: 20px; }
  h1 { font-size: 22px; font-weight: 700; }
  .subtitle { color: #6b7280; font-size: 12px; margin-top: 4px; }
  .meta-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin-bottom: 24px; }
  .meta-card { border: 1px solid #e5e7eb; border-radius: 8px; padding: 10px 14px; background: #f9fafb; }
  .meta-label { font-size: 10px; text-transform: uppercase; color: #6b7280; letter-spacing: 0.05em; margin-bottom: 4px; }
  .meta-value { font-size: 15px; font-weight: 700; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 24px; }
  thead th { background: #0D1420; color: #fff; font-size: 10px; text-transform: uppercase; letter-spacing: 0.05em; padding: 8px 10px; text-align: left; }
  tbody td { padding: 7px 10px; border-bottom: 1px solid #f3f4f6; vertical-align: top; }
  tbody tr:hover { background: #f9fafb; }
  .cap { text-transform: capitalize; }
  .mono { font-family: ui-monospace, monospace; font-size: 11px; }
  .total-row { margin-top: 8px; border: 2px solid #0D1420; border-radius: 8px; padding: 12px 16px; display: flex; justify-content: space-between; align-items: center; }
  .total-label { font-size: 13px; font-weight: 600; }
  .total-value { font-size: 18px; font-weight: 700; }
  .footer { margin-top: 40px; border-top: 1px solid #e5e7eb; padding-top: 12px; font-size: 10px; color: #9ca3af; display: flex; justify-content: space-between; }
  .no-print { display: block; }
  @media print {
    body { padding: 16px; }
    .no-print { display: none !important; }
    @page { margin: 12mm; }
  }
</style>
</head>
<body>

<div class="no-print" style="margin-bottom:18px;display:flex;justify-content:space-between;align-items:center">
  <span style="font-size:13px;font-weight:600;color:#6b7280">Insurance Claim Export · ${esc(property.name)}</span>
  <button onclick="window.print()" style="background:#0D1420;color:#fff;border:none;padding:8px 20px;border-radius:8px;cursor:pointer;font-size:12px;font-weight:600">Print / Save PDF</button>
</div>

<header>
  <h1>Insurance Claim — ${esc(property.name)}</h1>
  <p class="subtitle">Generated on ${now.toLocaleDateString('en', { year: 'numeric', month: 'long', day: 'numeric' })} &middot; Prepared by PRV HOUSE</p>
</header>

<div class="meta-grid">
  <div class="meta-card">
    <div class="meta-label">Property</div>
    <div class="meta-value">${esc(property.name)}</div>
  </div>
  <div class="meta-card">
    <div class="meta-label">Total items</div>
    <div class="meta-value">${itemList.length}</div>
  </div>
  <div class="meta-card">
    <div class="meta-label">Total declared value</div>
    <div class="meta-value">${currency} ${totalDeclaredValue.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</div>
  </div>
</div>

<table>
  <thead>
    <tr>
      <th>Item name</th>
      <th>Brand / Model</th>
      <th>Serial number</th>
      <th>Category</th>
      <th>Condition</th>
      <th>Purchase date</th>
      <th>Declared value</th>
    </tr>
  </thead>
  <tbody>
    ${tableRows}
  </tbody>
</table>

<div class="total-row">
  <span class="total-label">Total declared value</span>
  <span class="total-value">${currency} ${totalDeclaredValue.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</span>
</div>

<div class="footer">
  <span>PRV HOUSE Property Management &middot; ${esc(property.name)}</span>
  <span>Document generated: ${now.toISOString()}</span>
</div>
</body>
</html>`

  return new NextResponse(html, {
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  })
}
