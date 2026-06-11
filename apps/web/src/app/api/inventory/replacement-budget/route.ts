import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'

const LIFESPAN: Record<string, number> = {
  refrigerator: 15, washing_machine: 12, dishwasher: 10, oven: 15, microwave: 10,
  tv: 8, laptop: 5, phone: 3, sofa: 15, mattress: 10, water_heater: 12,
  hvac: 15, boiler: 15, default: 10,
}

export async function GET() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const property = await getActiveProperty(supabase, user.id)
  if (!property) return NextResponse.json({ error: 'No active property' }, { status: 404 })

  const { data: rawItems } = await (supabase.from('inventory_items') as any)
    .select('id, name, category, purchase_date, purchase_price, current_value')
    .eq('property_id', property.id)
  const items: Array<{ id: string; name: string; category: string | null; purchase_date: string | null; purchase_price: number | null; current_value: number | null }> = rawItems ?? []

  const now = new Date()
  const results = items.map((item) => {
    const category = (item.category ?? 'default').toLowerCase().replace(/\s+/g, '_')
    const lifespan = LIFESPAN[category] ?? LIFESPAN.default ?? 10
    const purchaseDate = item.purchase_date ? new Date(item.purchase_date) : null
    const ageYears = purchaseDate
      ? (now.getTime() - purchaseDate.getTime()) / (365.25 * 24 * 3600 * 1000)
      : 0
    const remainingYears = Math.max(0, lifespan - ageYears)
    const replacementCost = item.current_value ?? item.purchase_price ?? 500
    const monthlyBudget = remainingYears > 0
      ? replacementCost / (remainingYears * 12)
      : replacementCost / 12 // already at end of life, save for immediate replacement

    return {
      id: item.id,
      name: item.name,
      category: item.category,
      age_years: Math.round(ageYears * 10) / 10,
      remaining_years: Math.round(remainingYears * 10) / 10,
      monthly_budget: Math.round(monthlyBudget * 100) / 100,
      replacement_cost: replacementCost,
      lifespan,
    }
  })

  const total_monthly_budget = results.reduce((s, r) => s + r.monthly_budget, 0)

  return NextResponse.json({ items: results, total_monthly_budget: Math.round(total_monthly_budget * 100) / 100 })
}
