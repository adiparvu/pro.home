import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { InsightsPage } from '@/components/modules/insights/insights-page'

export const metadata: Metadata = { title: 'Insights' }

export interface InsightsData {
  stats: {
    ytdExpenses: number
    ytdIncome: number
    expenseCount: number
    openTasks: number
    overdueTasks: number
    avgMonthlyExpense: number
  }
  topCategories: { category: string; total: number; count: number }[]
  tasksByStatus: { status: string; count: number; color: string }[]
  monthlyTrend: { month: string; total: number }[]
  warrantyAlerts: { name: string; expiresAt: string; daysLeft: number }[]
}

const STATUS_COLORS: Record<string, string> = {
  pending: 'hsl(45,75%,42%)',
  in_progress: 'hsl(220,62%,52%)',
  completed: 'hsl(152,62%,42%)',
  overdue: 'hsl(0,68%,44%)',
}

export default async function InsightsRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)
  if (!property) redirect('/')

  const now = new Date()
  const yearStart = `${now.getFullYear()}-01-01`
  const in90 = new Date(now.getTime() + 90 * 86400_000).toISOString().split('T')[0]!
  const todayStr = now.toISOString().split('T')[0]!

  const [financesRes, tasksRes, inventoryRes] = await Promise.all([
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('financial_records').select('amount,type,category,date').eq('property_id', property.id).gte('date', yearStart).order('date', { ascending: false }).limit(200),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('maintenance_tasks').select('status,priority').eq('property_id', property.id).neq('status', 'cancelled').neq('status', 'completed'),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('inventory_items').select('name,warranty_expires').eq('property_id', property.id).not('warranty_expires', 'is', null),
  ])

  type FinRow = { amount: number; type: string; category: string; date: string }
  type TaskRow = { status: string; priority: string }
  type InvRow = { name: string; warranty_expires: string }

  const finances: FinRow[] = financesRes.data ?? []
  const tasks: TaskRow[] = tasksRes.data ?? []
  const inventory: InvRow[] = inventoryRes.data ?? []

  const expenses = finances.filter((f) => f.type === 'expense')
  const ytdExpenses = expenses.reduce((s, f) => s + f.amount, 0)
  const ytdIncome = finances.filter((f) => f.type === 'income').reduce((s, f) => s + f.amount, 0)

  // Top categories
  const catMap: Record<string, { total: number; count: number }> = {}
  for (const f of expenses) {
    const c = f.category ?? 'other'
    catMap[c] = catMap[c] ?? { total: 0, count: 0 }
    catMap[c]!.total += f.amount
    catMap[c]!.count += 1
  }
  const topCategories = Object.entries(catMap)
    .map(([category, v]) => ({ category, ...v }))
    .sort((a, b) => b.total - a.total)

  // Tasks by status
  const statusMap: Record<string, number> = {}
  for (const t of tasks) {
    statusMap[t.status] = (statusMap[t.status] ?? 0) + 1
  }
  const tasksByStatus = Object.entries(statusMap).map(([status, count]) => ({
    status,
    count,
    color: STATUS_COLORS[status] ?? 'hsl(210,75%,42%)',
  }))

  // Monthly trend (last 6 months)
  const monthlyMap: Record<string, number> = {}
  for (const f of expenses) {
    const m = f.date.slice(0, 7) // YYYY-MM
    monthlyMap[m] = (monthlyMap[m] ?? 0) + f.amount
  }
  const monthlyTrend = Object.entries(monthlyMap)
    .sort(([a], [b]) => a.localeCompare(b))
    .slice(-6)
    .map(([month, total]) => ({
      month: new Date(month + '-01').toLocaleDateString('en', { month: 'short' }),
      total: Math.round(total),
    }))

  const monthsWithData = new Set(expenses.map((f) => f.date.slice(0, 7))).size
  const avgMonthlyExpense = monthsWithData > 0 ? Math.round(ytdExpenses / monthsWithData) : 0

  // Warranty alerts
  const warrantyAlerts = inventory
    .filter((i) => i.warranty_expires > todayStr && i.warranty_expires < in90)
    .map((i) => {
      const daysLeft = Math.ceil((new Date(i.warranty_expires).getTime() - now.getTime()) / 86400_000)
      return { name: i.name, expiresAt: i.warranty_expires, daysLeft }
    })
    .sort((a, b) => a.daysLeft - b.daysLeft)

  const insightsData: InsightsData = {
    stats: {
      ytdExpenses: Math.round(ytdExpenses),
      ytdIncome: Math.round(ytdIncome),
      expenseCount: expenses.length,
      openTasks: tasks.filter((t) => t.status !== 'completed').length,
      overdueTasks: tasks.filter((t) => t.status === 'overdue').length,
      avgMonthlyExpense,
    },
    topCategories,
    tasksByStatus,
    monthlyTrend,
    warrantyAlerts,
  }

  return (
    <div className="flex flex-1 flex-col">
      <InsightsPage data={insightsData} propertyName={property.name} />
    </div>
  )
}
