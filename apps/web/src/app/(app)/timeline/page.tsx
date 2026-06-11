import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { TimelinePage } from '@/components/modules/timeline/timeline-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = {
  title: 'Timeline',
}

interface TimelineEvent {
  id: string
  source: 'maintenance' | 'finance' | 'document' | 'inventory' | 'valuation' | 'lease'
  title: string
  subtitle: string | null
  date: string
  meta?: string | null
}

export default async function TimelineRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Timeline" />
        <NoPropertyState />
      </div>
    )
  }

  // Fetch from all sources in parallel
  const [
    { data: maintenanceData },
    { data: financialData },
    { data: documentsData },
    { data: inventoryData },
    { data: valuationsData },
    { data: leasesData },
  ] = await Promise.all([
    supabase
      .from('maintenance_tasks')
      .select('id, title, status, category, created_at, updated_at')
      .eq('property_id', property.id)
      .order('created_at', { ascending: false })
      .limit(100),
    supabase
      .from('financial_records')
      .select('id, title, amount, currency, type, category, created_at')
      .eq('property_id', property.id)
      .order('created_at', { ascending: false })
      .limit(100),
    supabase
      .from('documents')
      .select('id, name, category, created_at')
      .eq('property_id', property.id)
      .order('created_at', { ascending: false })
      .limit(100),
    supabase
      .from('inventory_items')
      .select('id, name, category, created_at')
      .eq('property_id', property.id)
      .order('created_at', { ascending: false })
      .limit(100),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any)
      .from('property_valuations')
      .select('id, estimated_value, currency, source, valuation_date, created_at')
      .eq('property_id', property.id)
      .order('created_at', { ascending: false })
      .limit(100),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any)
      .from('leases')
      .select('id, tenant_name, status, start_date, created_at')
      .eq('property_id', property.id)
      .order('created_at', { ascending: false })
      .limit(100),
  ])

  const events: TimelineEvent[] = []

  // Map maintenance_tasks
  for (const task of (maintenanceData as any[] ?? [])) {
    events.push({
      id: `maintenance-created-${task.id}`,
      source: 'maintenance',
      title: task.title,
      subtitle: task.category ?? null,
      date: task.created_at,
    })
    if (task.status === 'completed' && task.updated_at) {
      events.push({
        id: `maintenance-completed-${task.id}`,
        source: 'maintenance',
        title: `Completed: ${task.title}`,
        subtitle: task.category ?? null,
        date: task.updated_at,
      })
    }
  }

  // Map financial_records
  for (const record of (financialData as any[] ?? [])) {
    events.push({
      id: `finance-${record.id}`,
      source: 'finance',
      title: record.title,
      subtitle: record.type && record.category ? `${record.type} · ${record.category}` : (record.type ?? record.category ?? null),
      date: record.created_at,
    })
  }

  // Map documents
  for (const doc of (documentsData as any[] ?? [])) {
    events.push({
      id: `document-${doc.id}`,
      source: 'document',
      title: doc.name,
      subtitle: doc.category ?? null,
      date: doc.created_at,
    })
  }

  // Map inventory_items
  for (const item of (inventoryData as any[] ?? [])) {
    events.push({
      id: `inventory-${item.id}`,
      source: 'inventory',
      title: item.name,
      subtitle: item.category ?? null,
      date: item.created_at,
    })
  }

  // Map property_valuations
  for (const val of (valuationsData as any[] ?? [])) {
    events.push({
      id: `valuation-${val.id}`,
      source: 'valuation',
      title: `Valuation: €${Number(val.estimated_value).toLocaleString()}`,
      subtitle: val.source ?? null,
      date: val.valuation_date ?? val.created_at,
    })
  }

  // Map leases
  for (const lease of (leasesData as any[] ?? [])) {
    events.push({
      id: `lease-${lease.id}`,
      source: 'lease',
      title: `Lease: ${lease.tenant_name}`,
      subtitle: lease.status ?? null,
      date: lease.start_date ?? lease.created_at,
    })
  }

  // Sort by date descending, take top 150
  events.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
  const top150 = events.slice(0, 150)

  return (
    <TimelinePage property={property} events={top150} />
  )
}
