import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'

interface ForecastItem {
  category: string
  avg_monthly: number
  next_month_forecast: number
  trend: 'up' | 'down' | 'stable'
  last3_avg: number
  last6_avg: number
}

interface ForecastResponse {
  forecasts: ForecastItem[]
  total_forecast: number
}

export async function GET() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const property = await getActiveProperty(supabase, user.id)
  if (!property) return NextResponse.json({ error: 'No active property' }, { status: 400 })

  const now = new Date()
  const twelveMonthsAgo = new Date(now.getFullYear(), now.getMonth() - 12, 1)
  const rangeStart = twelveMonthsAgo.toISOString().split('T')[0]!

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: records } = await (supabase as any)
    .from('financial_records')
    .select('category, amount, date')
    .eq('property_id', property.id)
    .eq('type', 'expense')
    .gte('date', rangeStart)
    .order('date', { ascending: true })
    .limit(2000) as {
      data: Array<{ category: string; amount: number; date: string }> | null
    }

  if (!records || records.length === 0) {
    const response: ForecastResponse = { forecasts: [], total_forecast: 0 }
    return NextResponse.json(response)
  }

  // Build a map: category -> { [yearMonth]: total }
  const categoryMonthMap: Record<string, Record<string, number>> = {}

  for (const r of records) {
    const ym = r.date.slice(0, 7) // "YYYY-MM"
    if (!categoryMonthMap[r.category]) categoryMonthMap[r.category] = {}
    categoryMonthMap[r.category]![ym] = (categoryMonthMap[r.category]![ym] ?? 0) + r.amount
  }

  // Build the last 12 months array of YYYY-MM strings (oldest first)
  const months: string[] = []
  for (let i = 11; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1)
    months.push(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`)
  }

  // Weights: oldest (index 0) = 1, last 3 months = higher weight
  // Pattern: [1,1,1,1,1,1,1,1,1,2,2,3] for indices 0..11
  const WEIGHTS = [1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 3]
  const WEIGHT_SUM = WEIGHTS.reduce((a, b) => a + b, 0)

  const forecasts: ForecastItem[] = []

  for (const [category, monthData] of Object.entries(categoryMonthMap)) {
    const monthlyAmounts = months.map((m) => monthData[m] ?? 0)

    // Weighted avg for next month forecast
    const weightedSum = monthlyAmounts.reduce((s, v, i) => s + v * (WEIGHTS[i] ?? 1), 0)
    const nextMonthForecast = weightedSum / WEIGHT_SUM

    // Simple avg over all 12 months
    const avgMonthly = monthlyAmounts.reduce((s, v) => s + v, 0) / 12

    // Last 3 avg (indices 9, 10, 11)
    const last3 = monthlyAmounts.slice(9)
    const last3Avg = last3.reduce((s, v) => s + v, 0) / 3

    // Last 6 avg (indices 6..11)
    const last6 = monthlyAmounts.slice(6)
    const last6Avg = last6.reduce((s, v) => s + v, 0) / 6

    // Trend: compare last3 vs previous 3 months
    const prev3 = monthlyAmounts.slice(6, 9)
    const prev3Avg = prev3.reduce((s, v) => s + v, 0) / 3
    const trendThreshold = 0.1 // 10%
    let trend: 'up' | 'down' | 'stable' = 'stable'
    if (prev3Avg > 0) {
      const change = (last3Avg - prev3Avg) / prev3Avg
      if (change > trendThreshold) trend = 'up'
      else if (change < -trendThreshold) trend = 'down'
    } else if (last3Avg > 0) {
      trend = 'up'
    }

    forecasts.push({
      category,
      avg_monthly: Math.round(avgMonthly * 100) / 100,
      next_month_forecast: Math.round(nextMonthForecast * 100) / 100,
      trend,
      last3_avg: Math.round(last3Avg * 100) / 100,
      last6_avg: Math.round(last6Avg * 100) / 100,
    })
  }

  // Sort by forecast descending
  forecasts.sort((a, b) => b.next_month_forecast - a.next_month_forecast)

  const total_forecast = forecasts.reduce((s, f) => s + f.next_month_forecast, 0)

  const response: ForecastResponse = {
    forecasts,
    total_forecast: Math.round(total_forecast * 100) / 100,
  }

  return NextResponse.json(response)
}
