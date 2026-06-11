import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { qrWithLogo } from '@/lib/qr-with-logo'

function esc(s: string | null | undefined): string {
  if (!s) return ''
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

function fmtDate(d: string | null) {
  if (!d) return null
  return new Date(d).toLocaleDateString('en', { day: 'numeric', month: 'short', year: 'numeric' })
}

export async function GET(req: NextRequest) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const property = await getActiveProperty(supabase, user.id)
  if (!property) return NextResponse.json({ error: 'No active property' }, { status: 400 })

  const { searchParams } = new URL(req.url)
  const roomId = searchParams.get('room_id')
  const roomName = searchParams.get('room_name')

  let query = supabase
    .from('inventory_items')
    .select('id, name, brand, model, category, serial_number, barcode, condition, purchase_date, warranty_expires, created_at')
    .eq('property_id', property.id)
    .order('name')

  if (roomId) {
    query = query.eq('room_id', roomId)
  }

  const { data: items } = await query as {
      data: Array<{
        id: string; name: string; brand: string | null; model: string | null
        category: string | null; serial_number: string | null; barcode: string | null
        condition: string | null; purchase_date: string | null
        warranty_expires: string | null; created_at: string
      }> | null
    }

  const itemList = items ?? []
  const baseUrl = process.env.NEXT_PUBLIC_APP_URL ?? 'https://app.prvhouse.com'

  const qrPromises = itemList.map(async (item) => {
    // QR links to the public item info page — no login required when scanned
    const url = `${baseUrl}/i/${item.id}`
    const svg = await qrWithLogo(url, { width: 90, margin: 1, dark: '#0D1420', light: '#ffffff' })
    return { item, svg }
  })

  const qrItems = await Promise.all(qrPromises)

  const labelRows = qrItems.map(({ item, svg }) => {
    const brandModel = [item.brand, item.model].filter(Boolean).join(' · ')
    const regDate = fmtDate(item.created_at)
    const purchaseDate = fmtDate(item.purchase_date)
    const warrantyDate = fmtDate(item.warranty_expires)
    return `<div class="label">
    ${svg}
    <div class="name">${esc(item.name)}</div>
    ${brandModel ? `<div class="sub">${esc(brandModel)}</div>` : ''}
    ${item.category ? `<div class="sub cap">${esc(item.category)}</div>` : ''}
    <div class="divider"></div>
    ${item.serial_number ? `<div class="sub mono">S/N: ${esc(item.serial_number.slice(0, 18))}</div>` : ''}
    ${item.barcode ? `<div class="sub mono">BC: ${esc(item.barcode.slice(0, 14))}</div>` : ''}
    ${item.condition ? `<div class="sub cap">${esc(item.condition.replace(/_/g, ' '))}</div>` : ''}
    ${purchaseDate ? `<div class="sub">Bought: ${esc(purchaseDate)}</div>` : ''}
    ${warrantyDate ? `<div class="sub">Warranty: ${esc(warrantyDate)}</div>` : ''}
    ${regDate ? `<div class="sub">Added: ${esc(regDate)}</div>` : ''}
    <div class="sub id">ID: ${item.id.slice(0, 8).toUpperCase()}</div>
  </div>`
  }).join('\n')

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>QR Labels — ${roomName ? esc(roomName) + ' · ' : ''}${esc(property.name)}</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; background: #fff; padding: 16px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(140px,1fr)); gap: 10px; }
  .label {
    border: 1px solid #e5e7eb; border-radius: 10px; padding: 10px 8px 8px;
    display: flex; flex-direction: column; align-items: center; gap: 3px;
    page-break-inside: avoid;
  }
  .label svg { width: 90px; height: 90px; display: block; }
  .name { font-size: 9.5px; font-weight: 700; text-align: center; color: #0D1420; line-height: 1.3; }
  .sub { font-size: 8px; color: #6b7280; text-align: center; }
  .sub.mono { font-family: ui-monospace, monospace; font-size: 7.5px; }
  .sub.cap { text-transform: capitalize; }
  .sub.id { opacity: 0.4; font-size: 7px; }
  .divider { width: 60%; height: 1px; background: #f3f4f6; margin: 3px 0; }
  @media print {
    body { padding: 8px; }
    .no-print { display: none; }
    @page { margin: 8mm; }
  }
</style>
</head>
<body>
<div class="no-print" style="margin-bottom:14px;display:flex;justify-content:space-between;align-items:center">
  <span style="font-size:13px;font-weight:600">${roomName ? esc(roomName) + ' · ' : ''}${esc(property.name)} — ${itemList.length} QR Labels</span>
  <button onclick="window.print()" style="background:#0D1420;color:#fff;border:none;padding:7px 18px;border-radius:8px;cursor:pointer;font-size:12px">Print labels</button>
</div>
<div class="grid">
${labelRows}
</div>
</body>
</html>`

  return new NextResponse(html, {
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  })
}
