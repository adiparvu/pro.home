import { type Metadata } from 'next'
import { createClient } from '@/lib/supabase/server'
import type { Property } from '@/lib/supabase/types'
import { DashboardHeader } from '@/components/modules/dashboard/dashboard-header'
import { HealthHeroCard } from '@/components/modules/dashboard/health-hero-card'
import { DashboardWidgetGrid } from '@/components/modules/dashboard/widget-grid'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = {
  title: 'Dashboard',
}

export default async function DashboardPage({
  searchParams,
}: {
  searchParams: Promise<{ p?: string }>
}) {
  const supabase = await createClient()
  const { p: requestedId } = await searchParams

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) return null

  const { data: properties } = await supabase
    .from('properties')
    .select('*, property_members!inner(role, status)')
    .eq('property_members.user_id', user.id)
    .eq('property_members.status', 'active')
    .eq('is_active', true)
    .order('created_at', { ascending: false }) as { data: Property[] | null; error: unknown }

  if (!properties || properties.length === 0) {
    return (
      <div className="flex flex-1 flex-col">
        <DashboardHeader user={user} />
        <NoPropertyState />
      </div>
    )
  }

  // Honour the ?p= selector if valid, otherwise fall back to first property
  const activeProperty =
    (requestedId ? properties.find((p) => p.id === requestedId) : null) ?? properties[0]!

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sb = supabase as any

  // Mark any past-due tasks as overdue before reading counts (fires notification trigger)
  await sb.rpc('mark_overdue_tasks', { p_property_id: activeProperty.id })

  const today = new Date().toISOString().split('T')[0]
  const monthStart = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().split('T')[0]

  // Fetch dashboard data in parallel
  const [r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12] = await Promise.all([
    supabase.from('maintenance_tasks').select('*', { count: 'exact', head: true })
      .eq('property_id', activeProperty.id).in('status', ['pending', 'in_progress']),
    supabase.from('maintenance_tasks').select('*', { count: 'exact', head: true })
      .eq('property_id', activeProperty.id).eq('status', 'overdue'),
    supabase.from('notifications').select('*', { count: 'exact', head: true })
      .eq('user_id', user.id).eq('status', 'unread'),
    supabase.from('inventory_items').select('*', { count: 'exact', head: true })
      .eq('property_id', activeProperty.id),
    supabase.from('inventory_items').select('*', { count: 'exact', head: true })
      .eq('property_id', activeProperty.id).eq('recall_active', true),
    supabase.from('maintenance_tasks')
      .select('id, title')
      .eq('property_id', activeProperty.id)
      .eq('status', 'overdue')
      .order('due_date', { ascending: true, nullsFirst: true })
      .limit(1),
    supabase.from('documents')
      .select('*', { count: 'exact', head: true })
      .eq('property_id', activeProperty.id)
      .not('expires_at', 'is', null)
      .lte('expires_at', new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString())
      .gt('expires_at', new Date().toISOString()),
    // Latest energy reading for the property
    sb.from('energy_readings')
      .select('reading_value, unit, meter_type, reading_date')
      .eq('property_id', activeProperty.id)
      .order('reading_date', { ascending: false })
      .limit(1),
    // Security arm/disarm state
    sb.from('security_state')
      .select('mode')
      .eq('property_id', activeProperty.id)
      .maybeSingle(),
    // Garden: plants needing water (overdue or due today)
    sb.from('garden_plants')
      .select('*', { count: 'exact', head: true })
      .eq('property_id', activeProperty.id)
      .not('next_watering', 'is', null)
      .lte('next_watering', today),
    // Garden: pending tasks
    sb.from('garden_tasks')
      .select('*', { count: 'exact', head: true })
      .eq('property_id', activeProperty.id)
      .in('status', ['pending', 'scheduled']),
    // Finances: this-month expenses total
    sb.from('financial_records')
      .select('amount')
      .eq('property_id', activeProperty.id)
      .eq('type', 'expense')
      .gte('date', monthStart),
    // Finances: this-month income total
    sb.from('financial_records')
      .select('amount')
      .eq('property_id', activeProperty.id)
      .eq('type', 'income')
      .gte('date', monthStart),
  ])

  const upcomingTasksCount = r0.count ?? 0
  const overdueTasksCount = r1.count ?? 0
  const unreadNotifications = r2.count ?? 0
  const inventoryCount = r3.count ?? 0
  const recallCount = r4.count ?? 0
  const topOverdueTitle = (r5.data as { id: string; title: string }[] | null)?.[0]?.title ?? null
  const expiringDocsCount = r6.count ?? 0
  const latestEnergyRow = (r7.data as { reading_value: number; unit: string; meter_type: string; reading_date: string }[] | null)?.[0] ?? null
  const securityMode = (r8.data as { mode: string } | null)?.mode ?? null
  const overdueWateringCount = r9.count ?? 0
  const pendingGardenTasksCount = r10.count ?? 0
  const monthlyExpenses = ((r11.data as { amount: number }[] | null) ?? []).reduce((s, x) => s + x.amount, 0)
  const monthlyIncome = ((r12.data as { amount: number }[] | null) ?? []).reduce((s, x) => s + x.amount, 0)

  const ariaInsight = getAriaInsight(
    overdueTasksCount,
    upcomingTasksCount,
    recallCount,
    expiringDocsCount,
    topOverdueTitle,
  )

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <DashboardHeader
        user={user}
        notificationCount={unreadNotifications}
        properties={properties}
        activeProperty={activeProperty}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        <HealthHeroCard
          property={activeProperty}
          overdueTasksCount={overdueTasksCount}
          upcomingTasksCount={upcomingTasksCount}
          recallCount={recallCount}
        />

        <DashboardWidgetGrid
          upcomingTasksCount={upcomingTasksCount}
          overdueTasksCount={overdueTasksCount}
          inventoryCount={inventoryCount}
          recallCount={recallCount}
          ariaInsight={ariaInsight}
          expiringDocsCount={expiringDocsCount}
          latestEnergyValue={latestEnergyRow?.reading_value ?? null}
          latestEnergyUnit={latestEnergyRow?.unit ?? null}
          latestEnergyMeterType={latestEnergyRow?.meter_type ?? null}
          securityMode={securityMode}
          overdueWateringCount={overdueWateringCount}
          pendingGardenTasksCount={pendingGardenTasksCount}
          monthlyExpenses={monthlyExpenses}
          monthlyIncome={monthlyIncome}
        />
      </div>
    </div>
  )
}

function getAriaInsight(
  overdueCount: number,
  upcomingCount: number,
  recallCount: number,
  expiringDocsCount: number,
  topOverdueTitle: string | null,
): string {
  if (overdueCount > 0) {
    const more = overdueCount - 1
    const base = topOverdueTitle
      ? `"${topOverdueTitle}" is overdue${more > 0 ? ` — and ${more} more task${more !== 1 ? 's' : ''}` : ''}`
      : `${overdueCount} maintenance task${overdueCount !== 1 ? 's are' : ' is'} overdue`
    return `${base}. Address these to keep your home healthy.`
  }
  if (recallCount > 0) {
    return `${recallCount} item${recallCount !== 1 ? 's' : ''} in your inventory ${recallCount !== 1 ? 'have' : 'has'} active safety recalls. Review your inventory promptly.`
  }
  if (expiringDocsCount > 0) {
    return `${expiringDocsCount} document${expiringDocsCount !== 1 ? 's expire' : ' expires'} within 30 days. Review your documents to stay covered.`
  }
  if (upcomingCount > 0) {
    return `${upcomingCount} task${upcomingCount !== 1 ? 's are' : ' is'} upcoming. Your home maintenance is on schedule.`
  }
  return 'Your home systems are looking good. Ask ARIA about seasonal care, energy savings, or any home question.'
}
