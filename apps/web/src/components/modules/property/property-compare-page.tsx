'use client'

import * as React from 'react'
import { BarChart3, Home, AlertCircle, Package, DollarSign, Wrench } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { Card } from '@/components/ui/card'
import type { Property } from '@/lib/supabase/types'

interface PropertyMetrics {
  propertyId: string
  maintenanceTasks: number
  openTasks: number
  inventoryItems: number
  totalExpenses: number
  currency: string
}

interface PropertyComparePageProps {
  properties: Property[]
}

const METRIC_CONFIG = [
  { key: 'maintenanceTasks', label: 'All Tasks', icon: Wrench, color: 'hsl(220,70%,55%)' },
  { key: 'openTasks', label: 'Open Tasks', icon: AlertCircle, color: 'hsl(45,75%,42%)' },
  { key: 'inventoryItems', label: 'Inventory Items', icon: Package, color: 'hsl(152,62%,38%)' },
  { key: 'totalExpenses', label: 'Total Expenses', icon: DollarSign, color: 'hsl(0,68%,44%)' },
] as const

export function PropertyComparePage({ properties }: PropertyComparePageProps) {
  const [metrics, setMetrics] = React.useState<Record<string, PropertyMetrics>>({})
  const [loading, setLoading] = React.useState(true)

  React.useEffect(() => {
    if (properties.length === 0) { setLoading(false); return }

    async function fetchAll() {
      const supabase = createClient()
      const results: Record<string, PropertyMetrics> = {}

      await Promise.all(
        properties.map(async (p) => {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const sb = supabase as any
          const [tasks, items, expenses] = await Promise.all([
            sb.from('maintenance_tasks').select('id, status').eq('property_id', p.id),
            sb.from('inventory_items').select('id').eq('property_id', p.id),
            sb.from('financial_records').select('amount').eq('property_id', p.id).eq('type', 'expense'),
          ])

          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const allTasks: any[] = tasks.data ?? []
          const openTasks = allTasks.filter((t) => t.status !== 'done' && t.status !== 'archived').length

          results[p.id] = {
            propertyId: p.id,
            maintenanceTasks: allTasks.length,
            openTasks,
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            inventoryItems: ((items.data ?? []) as any[]).length,
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            totalExpenses: ((expenses.data ?? []) as any[]).reduce((s: number, r: any) => s + (r.amount ?? 0), 0),
            currency: 'EUR',
          }
        })
      )

      setMetrics(results)
      setLoading(false)
    }

    fetchAll()
  }, [properties])

  if (properties.length === 0) {
    return (
      <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground px-4">
        <Home className="h-10 w-10 opacity-30" />
        <p className="text-sm">No properties to compare</p>
        <p className="text-xs opacity-60">Add more properties to see a comparison</p>
      </div>
    )
  }

  if (properties.length === 1) {
    return (
      <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground px-4">
        <BarChart3 className="h-10 w-10 opacity-30" />
        <p className="text-sm">Only one property</p>
        <p className="text-xs opacity-60">Add another property to compare side-by-side</p>
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
      {/* Scrollable comparison table */}
      <div className="overflow-x-auto -mx-4 px-4 md:-mx-6 md:px-6">
        <div className="min-w-[480px]">
      {/* Property header row */}
      <div className="grid gap-3 mb-4" style={{ gridTemplateColumns: `160px repeat(${properties.length}, 1fr)` }}>
        <div />
        {properties.map((p) => (
          <Card key={p.id} className="p-3 text-center">
            <div className="flex h-9 w-9 mx-auto items-center justify-center rounded-lg bg-primary/10 mb-2">
              <Home className="h-4 w-4 text-primary" />
            </div>
            <p className="text-sm font-semibold truncate">{p.name}</p>
            {p.address_line1 && <p className="text-xs text-muted-foreground truncate mt-0.5">{p.address_line1}</p>}
          </Card>
        ))}
      </div>

      {/* Metric rows */}
      <div className="flex flex-col gap-3">
      {METRIC_CONFIG.map(({ key, label, icon: Icon, color }) => {
        const values = properties.map((p) => {
          const m = metrics[p.id]
          if (!m) return null
          return m[key as keyof PropertyMetrics] as number
        })
        const maxVal = Math.max(...values.filter((v): v is number => v !== null), 1)

        return (
          <div
            key={key}
            className="grid gap-3 items-center"
            style={{ gridTemplateColumns: `160px repeat(${properties.length}, 1fr)` }}
          >
            <div className="flex items-center gap-2">
              <div
                className="flex h-7 w-7 items-center justify-center rounded-lg shrink-0"
                style={{ background: color + '20', color }}
              >
                <Icon className="h-3.5 w-3.5" />
              </div>
              <span className="text-sm text-muted-foreground">{label}</span>
            </div>

            {properties.map((p, i) => {
              const val = values[i] ?? null
              const pct = val !== null && maxVal > 0 ? (val / maxVal) * 100 : 0
              const isMax = val !== null && val === maxVal && maxVal > 0

              return (
                <Card key={p.id} className="p-3">
                  {loading ? (
                    <div className="h-8 animate-pulse bg-muted/40 rounded" />
                  ) : (
                    <div className="space-y-1.5">
                      <p
                        className="text-lg font-semibold"
                        style={{ color: isMax && key === 'openTasks' ? 'hsl(0,68%,44%)' : isMax ? color : undefined }}
                      >
                        {key === 'totalExpenses' && val !== null
                          ? `${val.toLocaleString('en', { maximumFractionDigits: 0 })} EUR`
                          : (val ?? '—')}
                      </p>
                      <div className="h-1.5 w-full rounded-full bg-muted">
                        <div
                          className="h-full rounded-full transition-all"
                          style={{ width: `${pct}%`, background: color }}
                        />
                      </div>
                    </div>
                  )}
                </Card>
              )
            })}
          </div>
        )
      })}
      </div>
        </div>
      </div>
    </div>
  )
}
