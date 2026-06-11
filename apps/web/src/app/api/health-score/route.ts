import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'

export async function GET(req: Request) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const url = new URL(req.url)
  const propertyIdParam = url.searchParams.get('property_id')

  let property
  if (propertyIdParam) {
    // Verify the user is a member of this property
    const { data: membership } = await supabase
      .from('property_members')
      .select('id')
      .eq('property_id', propertyIdParam)
      .eq('user_id', user.id)
      .eq('status', 'active')
      .maybeSingle()
    if (!membership) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    const { data: prop } = await supabase.from('properties').select('*').eq('id', propertyIdParam).maybeSingle()
    property = prop
  } else {
    property = await getActiveProperty(supabase, user.id)
  }
  if (!property) return NextResponse.json({ error: 'No active property' }, { status: 404 })

  const sb = supabase as any // eslint-disable-line @typescript-eslint/no-explicit-any
  const now = new Date()

  const [tasksResult, financesResult, docsResult, inventoryResult, warrantiesResult] = await Promise.all([
    // Maintenance tasks
    supabase
      .from('maintenance_tasks')
      .select('status')
      .eq('property_id', property.id)
      .in('status', ['pending', 'in_progress', 'overdue']),

    // Financial records last 6 months
    sb
      .from('financial_records')
      .select('date')
      .eq('property_id', property.id)
      .gte('date', new Date(now.getFullYear(), now.getMonth() - 5, 1).toISOString().split('T')[0]),

    // Documents with expiry
    supabase
      .from('documents')
      .select('expires_at')
      .eq('property_id', property.id)
      .not('expires_at', 'is', null),

    // Inventory with recalls
    supabase
      .from('inventory_items')
      .select('recall_active, warranty_expires')
      .eq('property_id', property.id),

    // Inventory items with warranty_expires
    supabase
      .from('inventory_items')
      .select('warranty_expires')
      .eq('property_id', property.id)
      .not('warranty_expires', 'is', null),
  ])

  // --- Maintenance (30 pts) ---
  const tasks = (tasksResult.data ?? []) as { status: string }[]
  const overdueTasks = tasks.filter((t) => t.status === 'overdue').length
  const pendingTasks = tasks.filter((t) => t.status === 'pending' || t.status === 'in_progress').length
  const maintenanceRaw = Math.max(0, 100 - Math.min(100, overdueTasks * 15 + pendingTasks * 3))
  const maintenanceScore = Math.round((maintenanceRaw / 100) * 30)

  // --- Finances (25 pts) ---
  const finRecords = (financesResult.data ?? []) as { date: string }[]
  const monthsWithData = new Set(finRecords.map((r) => r.date.substring(0, 7))).size
  const financesRaw = (monthsWithData / 6) * 100
  const financesScore = Math.round((financesRaw / 100) * 25)

  // --- Documents (20 pts) ---
  const docs = (docsResult.data ?? []) as { expires_at: string | null }[]
  const expiredDocs = docs.filter((d) => d.expires_at && new Date(d.expires_at) < now).length
  const documentsRaw = Math.max(0, 100 - expiredDocs * 20)
  const documentsScore = Math.round((documentsRaw / 100) * 20)

  // --- Inventory (15 pts) ---
  const inventoryItems = (inventoryResult.data ?? []) as { recall_active: boolean | null; warranty_expires: string | null }[]
  const itemsWithRecall = inventoryItems.filter((i) => i.recall_active).length
  const inventoryRaw = Math.max(0, 100 - itemsWithRecall * 25)
  const inventoryScore = Math.round((inventoryRaw / 100) * 15)

  // --- Warranties (10 pts) ---
  const warrantyItems = (warrantiesResult.data ?? []) as { warranty_expires: string | null }[]
  const expiredWarranties = warrantyItems.filter((i) => i.warranty_expires && new Date(i.warranty_expires) < now).length
  const warrantiesRaw = Math.max(0, 100 - expiredWarranties * 10)
  const warrantiesScore = Math.round((warrantiesRaw / 100) * 10)

  const score = maintenanceScore + financesScore + documentsScore + inventoryScore + warrantiesScore

  const grade =
    score >= 90 ? 'A' :
    score >= 75 ? 'B' :
    score >= 60 ? 'C' :
    score >= 40 ? 'D' : 'F'

  // Simple trend: compare to property.health_score if it exists
  const previousScore = property.health_score
  const trend: 'up' | 'stable' | 'down' =
    previousScore == null ? 'stable' :
    score > previousScore + 3 ? 'up' :
    score < previousScore - 3 ? 'down' : 'stable'

  return NextResponse.json({
    score,
    breakdown: {
      maintenance: maintenanceScore,
      finances: financesScore,
      documents: documentsScore,
      inventory: inventoryScore,
      warranties: warrantiesScore,
    },
    grade,
    trend,
  })
}
