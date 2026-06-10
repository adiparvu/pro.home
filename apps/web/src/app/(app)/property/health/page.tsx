import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import type { Property, MaintenanceTask, InventoryItem, Document, PropertyHealthHistory } from '@/lib/supabase/types'
import { HealthReport } from '@/components/modules/property/health-report'

export const metadata: Metadata = { title: 'Property Health' }

async function recordHistory(supabase: Awaited<ReturnType<typeof createClient>>, propertyId: string, score: number) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (supabase as any).from('property_health_history').insert({ property_id: propertyId, score })
}

async function refreshScore(propertyId: string) {
  'use server'
  const supabase = await createClient()
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: score } = await (supabase as any).rpc('compute_health_score', {
    p_property_id: propertyId,
  }) as { data: number | null; error: unknown }
  if (score !== null) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any)
      .from('properties')
      .update({ health_score: score, health_updated_at: new Date().toISOString() })
      .eq('id', propertyId)
    await recordHistory(supabase, propertyId, score)
  }
  revalidatePath('/property/health')
}

export default async function PropertyHealthPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: property } = await supabase
    .from('properties')
    .select('*, property_members!inner(role, status)')
    .eq('property_members.user_id', user.id)
    .eq('property_members.status', 'active')
    .eq('is_active', true)
    .order('created_at', { ascending: false })
    .limit(1)
    .single() as { data: Property | null; error: unknown }

  if (!property) redirect('/')

  // Mark any past-due tasks as overdue before health score computation
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (supabase as any).rpc('mark_overdue_tasks', { p_property_id: property.id })

  // Auto-compute if score has never been set
  if (property.health_score === null) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: score } = await (supabase as any).rpc('compute_health_score', {
      p_property_id: property.id,
    }) as { data: number | null; error: unknown }
    if (score !== null) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any)
        .from('properties')
        .update({ health_score: score, health_updated_at: new Date().toISOString() })
        .eq('id', property.id)
      await recordHistory(supabase, property.id, score)
      ;(property as { health_score: number | null }).health_score = score
      ;(property as { health_updated_at: string | null }).health_updated_at = new Date().toISOString()
    }
  }

  const [r0, r1, r2, r3, r4, r5, r6] = await Promise.all([
    supabase.from('maintenance_tasks').select('*', { count: 'exact', head: true })
      .eq('property_id', property.id).in('status', ['pending', 'in_progress']),
    supabase.from('maintenance_tasks').select('*', { count: 'exact', head: true })
      .eq('property_id', property.id).eq('status', 'overdue'),
    supabase.from('inventory_items').select('*', { count: 'exact', head: true })
      .eq('property_id', property.id).eq('recall_active', true),
    supabase.from('maintenance_tasks')
      .select('id, title, priority, due_date, status, category')
      .eq('property_id', property.id)
      .eq('status', 'overdue')
      .order('due_date', { ascending: true, nullsFirst: true })
      .limit(5),
    supabase.from('inventory_items')
      .select('id, name, brand, model')
      .eq('property_id', property.id)
      .eq('recall_active', true)
      .limit(5),
    supabase.from('documents')
      .select('id, name, category, expires_at')
      .eq('property_id', property.id)
      .not('expires_at', 'is', null)
      .lte('expires_at', new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString())
      .gt('expires_at', new Date().toISOString())
      .order('expires_at', { ascending: true })
      .limit(5),
    // Health score history — last 30 snapshots
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any)
      .from('property_health_history')
      .select('score, recorded_at')
      .eq('property_id', property.id)
      .order('recorded_at', { ascending: true })
      .limit(30) as Promise<{ data: Pick<PropertyHealthHistory, 'score' | 'recorded_at'>[] | null }>,
  ])

  const upcomingCount = r0.count ?? 0
  const overdueCount = r1.count ?? 0
  const recallCount = r2.count ?? 0
  const overdueTasks = (r3.data ?? []) as Pick<MaintenanceTask, 'id' | 'title' | 'priority' | 'due_date' | 'status' | 'category'>[]
  const recallItems = (r4.data ?? []) as Pick<InventoryItem, 'id' | 'name' | 'brand' | 'model'>[]
  const expiringDocs = (r5.data ?? []) as Pick<Document, 'id' | 'name' | 'category' | 'expires_at'>[]
  const scoreHistory = (r6.data ?? []) as Pick<PropertyHealthHistory, 'score' | 'recorded_at'>[]

  const refreshScoreForProperty = refreshScore.bind(null, property.id)

  return (
    <HealthReport
      property={property}
      overdueCount={overdueCount}
      upcomingCount={upcomingCount}
      recallCount={recallCount}
      overdueTasks={overdueTasks}
      recallItems={recallItems}
      expiringDocs={expiringDocs}
      refreshScoreAction={refreshScoreForProperty}
      scoreHistory={scoreHistory}
    />
  )
}
