import { NextRequest, NextResponse } from 'next/server'
import QRCode from 'qrcode'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'

export async function GET(req: NextRequest) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const property = await getActiveProperty(supabase, user.id)
  if (!property) return NextResponse.json({ error: 'No active property' }, { status: 400 })

  const { data: items } = await supabase
    .from('inventory_items')
    .select('id, name, brand, category, serial_number')
    .eq('property_id', property.id)
    .order('name') as { data: Array<{ id: string; name: string; brand: string | null; category: string | null; serial_number: string | null }> | null }

  const itemList = items ?? []

  const qrPromises = itemList.map(async (item) => {
    const url = `${process.env.NEXT_PUBLIC_APP_URL ?? 'https://app.prvhouse.com'}/inventory?item=${item.id}`
    const svg = await QRCode.toString(url, { type: 'svg', width: 80, margin: 1, color: { dark: '#1a1a2e', light: '#ffffff' } })
    return { item, svg }
  })

  const qrItems = await Promise.all(qrPromises)

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>QR Labels — ${property.name}</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; background: #fff; padding: 16px; }
  h1 { font-size: 14px; font-weight: 600; margin-bottom: 16px; color: #6b7280; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(120px,1fr)); gap: 8px; }
  .label { border: 1px solid #e5e7eb; border-radius: 8px; padding: 8px; display: flex; flex-direction: column; align-items: center; gap: 4px; page-break-inside: avoid; }
  .label svg { width: 80px; height: 80px; display: block; }
  .name { font-size: 9px; font-weight: 600; text-align: center; color: #1a1a2e; line-height: 1.3; max-width: 108px; overflow: hidden; }
  .sub { font-size: 8px; color: #6b7280; text-align: center; }
  @media print {
    body { padding: 8px; }
    .no-print { display: none; }
    @page { margin: 8mm; }
  }
</style>
</head>
<body>
<div class="no-print" style="margin-bottom:12px;display:flex;justify-content:space-between;align-items:center">
  <span style="font-size:13px;font-weight:600">${property.name} — ${itemList.length} QR Labels</span>
  <button onclick="window.print()" style="background:#1a1a2e;color:#fff;border:none;padding:6px 16px;border-radius:6px;cursor:pointer;font-size:12px">Print labels</button>
</div>
<div class="grid">
  ${qrItems.map(({ item, svg }) => `
  <div class="label">
    ${svg}
    <div class="name">${item.name}</div>
    ${item.brand ? `<div class="sub">${item.brand}</div>` : ''}
    ${item.category ? `<div class="sub">${item.category}</div>` : ''}
    ${item.serial_number ? `<div class="sub" style="font-family:monospace">${item.serial_number.slice(0,12)}</div>` : ''}
  </div>`).join('')}
</div>
</body>
</html>`

  return new NextResponse(html, {
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
    },
  })
}
