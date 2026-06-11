import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'

export async function GET(req: NextRequest) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const property = await getActiveProperty(supabase, user.id)
  if (!property) return NextResponse.json({ error: 'No active property' }, { status: 400 })

  const now = new Date()
  const yearStart = `${now.getFullYear()}-01-01`

  const [tasksRes, financesRes, inventoryRes, docsRes, membersRes] = await Promise.all([
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('maintenance_tasks').select('title,status,priority,due_date,category,cost,completed_date').eq('property_id', property.id).neq('status','cancelled').order('due_date', { ascending: true }).limit(100),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('financial_records').select('title,amount,type,category,date').eq('property_id', property.id).gte('date', yearStart).order('date', { ascending: false }).limit(100),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('inventory_items').select('name,brand,category,condition,purchase_year,warranty_expires').eq('property_id', property.id).order('name').limit(100),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('documents').select('name,category,expires_at,is_critical').eq('property_id', property.id).order('created_at', { ascending: false }).limit(50),
    supabase.from('property_members').select('role, profiles(display_name, email)').eq('property_id', property.id).eq('status','active'),
  ])

  const tasks: Array<{ title: string; status: string; priority: string; due_date: string | null; category: string | null; cost: number | null }> = tasksRes.data ?? []
  const finances: Array<{ title: string; amount: number; type: string; category: string; date: string }> = financesRes.data ?? []
  const inventory: Array<{ name: string; brand: string | null; category: string | null; condition: string | null; purchase_year: number | null; warranty_expires: string | null }> = inventoryRes.data ?? []
  const docs: Array<{ name: string; category: string; expires_at: string | null; is_critical: boolean }> = docsRes.data ?? []

  const ytdExpenses = finances.filter((f) => f.type === 'expense').reduce((s, f) => s + f.amount, 0)
  const ytdIncome = finances.filter((f) => f.type === 'income').reduce((s, f) => s + f.amount, 0)
  const overdueTasks = tasks.filter((t) => t.status === 'overdue')
  const pendingTasks = tasks.filter((t) => t.status === 'pending' || t.status === 'in_progress')

  const expiringDocs = docs.filter((d) => {
    if (!d.expires_at) return false
    const in90 = new Date(now.getTime() + 90 * 86400_000).toISOString().split('T')[0]!
    return d.expires_at > now.toISOString().split('T')[0]! && d.expires_at < in90
  })

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Property Report — ${property.name}</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, -apple-system, sans-serif; font-size: 12px; color: #1a1a2e; line-height: 1.5; padding: 32px; background: #fff; }
  h1 { font-size: 22px; font-weight: 700; margin-bottom: 4px; }
  h2 { font-size: 15px; font-weight: 600; margin: 24px 0 8px; border-bottom: 1px solid #e5e7eb; padding-bottom: 4px; }
  h3 { font-size: 13px; font-weight: 600; margin-bottom: 6px; }
  .meta { color: #6b7280; font-size: 11px; margin-bottom: 24px; }
  .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 16px; }
  .kpi { background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 8px; padding: 12px; }
  .kpi-label { font-size: 10px; color: #6b7280; text-transform: uppercase; letter-spacing: 0.05em; }
  .kpi-value { font-size: 18px; font-weight: 700; color: #111827; margin-top: 2px; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 8px; }
  th { text-align: left; font-size: 10px; text-transform: uppercase; letter-spacing: 0.05em; color: #6b7280; padding: 6px 8px; border-bottom: 1px solid #e5e7eb; }
  td { padding: 6px 8px; border-bottom: 1px solid #f3f4f6; font-size: 11px; }
  tr:last-child td { border-bottom: none; }
  .badge { display: inline-block; padding: 1px 6px; border-radius: 9999px; font-size: 10px; font-weight: 600; }
  .badge-red { background: #fef2f2; color: #dc2626; }
  .badge-yellow { background: #fffbeb; color: #d97706; }
  .badge-green { background: #f0fdf4; color: #16a34a; }
  .badge-gray { background: #f9fafb; color: #6b7280; }
  .footer { margin-top: 32px; padding-top: 16px; border-top: 1px solid #e5e7eb; font-size: 10px; color: #9ca3af; display: flex; justify-content: space-between; }
  @media print { body { padding: 16px; } }
</style>
</head>
<body>
<h1>${property.name}</h1>
<p class="meta">
  ${property.property_type ?? 'Property'} ·
  ${property.size_sqm ? property.size_sqm + ' m²' : ''} ·
  ${property.city ? property.city + ', ' : ''}${property.country ?? ''} ·
  Built ${property.year_built ?? '—'} ·
  Report generated ${now.toLocaleDateString('en', { year: 'numeric', month: 'long', day: 'numeric' })}
</p>

<div class="grid">
  <div class="kpi">
    <div class="kpi-label">Health score</div>
    <div class="kpi-value">${property.health_score ?? '—'}/100</div>
  </div>
  <div class="kpi">
    <div class="kpi-label">YTD expenses</div>
    <div class="kpi-value">€${ytdExpenses.toFixed(0)}</div>
  </div>
  <div class="kpi">
    <div class="kpi-label">Overdue tasks</div>
    <div class="kpi-value">${overdueTasks.length}</div>
  </div>
  <div class="kpi">
    <div class="kpi-label">Inventory items</div>
    <div class="kpi-value">${inventory.length}</div>
  </div>
</div>

<h2>Maintenance Tasks</h2>
${tasks.length === 0 ? '<p style="color:#6b7280">No open tasks.</p>' : `
<table>
  <thead><tr><th>Task</th><th>Category</th><th>Priority</th><th>Status</th><th>Due</th><th>Cost</th></tr></thead>
  <tbody>
    ${tasks.map((t) => `<tr>
      <td>${t.title}</td>
      <td>${t.category ?? '—'}</td>
      <td><span class="badge ${t.priority === 'critical' ? 'badge-red' : t.priority === 'high' ? 'badge-yellow' : 'badge-gray'}">${t.priority}</span></td>
      <td><span class="badge ${t.status === 'completed' ? 'badge-green' : t.status === 'overdue' ? 'badge-red' : 'badge-gray'}">${t.status}</span></td>
      <td>${t.due_date ?? '—'}</td>
      <td>${t.cost != null ? '€' + t.cost.toFixed(0) : '—'}</td>
    </tr>`).join('')}
  </tbody>
</table>`}

<h2>Finances (Year to Date)</h2>
<p style="margin-bottom:12px;font-size:11px;color:#6b7280">
  Total income: <strong>€${ytdIncome.toFixed(0)}</strong> ·
  Total expenses: <strong>€${ytdExpenses.toFixed(0)}</strong> ·
  Net: <strong style="color:${ytdIncome - ytdExpenses >= 0 ? '#16a34a' : '#dc2626'}">€${(ytdIncome - ytdExpenses).toFixed(0)}</strong>
</p>
${finances.length > 0 ? `
<table>
  <thead><tr><th>Date</th><th>Title</th><th>Category</th><th>Type</th><th>Amount</th></tr></thead>
  <tbody>
    ${finances.slice(0, 30).map((f) => `<tr>
      <td>${f.date}</td>
      <td>${f.title}</td>
      <td>${f.category}</td>
      <td><span class="badge ${f.type === 'income' ? 'badge-green' : 'badge-red'}">${f.type}</span></td>
      <td>€${f.amount.toFixed(0)}</td>
    </tr>`).join('')}
  </tbody>
</table>` : '<p style="color:#6b7280">No financial records this year.</p>'}

<h2>Inventory (${inventory.length} items)</h2>
${inventory.length > 0 ? `
<table>
  <thead><tr><th>Item</th><th>Brand</th><th>Category</th><th>Condition</th><th>Year</th><th>Warranty</th></tr></thead>
  <tbody>
    ${inventory.map((i) => `<tr>
      <td>${i.name}</td>
      <td>${i.brand ?? '—'}</td>
      <td>${i.category ?? '—'}</td>
      <td><span class="badge ${i.condition === 'poor' || i.condition === 'broken' ? 'badge-red' : i.condition === 'fair' ? 'badge-yellow' : 'badge-green'}">${i.condition ?? '—'}</span></td>
      <td>${i.purchase_year ?? '—'}</td>
      <td>${i.warranty_expires ?? '—'}</td>
    </tr>`).join('')}
  </tbody>
</table>` : '<p style="color:#6b7280">No inventory items.</p>'}

<h2>Documents (${docs.length} total${expiringDocs.length > 0 ? ` · ${expiringDocs.length} expiring soon` : ''})</h2>
${docs.length > 0 ? `
<table>
  <thead><tr><th>Document</th><th>Category</th><th>Expires</th><th>Critical</th></tr></thead>
  <tbody>
    ${docs.map((d) => `<tr>
      <td>${d.name}</td>
      <td>${d.category}</td>
      <td>${d.expires_at ?? '—'}</td>
      <td>${d.is_critical ? '<span class="badge badge-red">Yes</span>' : '—'}</td>
    </tr>`).join('')}
  </tbody>
</table>` : '<p style="color:#6b7280">No documents.</p>'}

<div class="footer">
  <span>PRV HOUSE · ${property.name}</span>
  <span>Generated ${now.toISOString()}</span>
</div>
</body>
</html>`

  return new NextResponse(html, {
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Disposition': `inline; filename="property-report-${property.id.slice(0,8)}-${now.toISOString().split('T')[0]}.html"`,
    },
  })
}
