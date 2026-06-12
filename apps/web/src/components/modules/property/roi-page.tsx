'use client'

import * as React from 'react'
import { TrendingUp, TrendingDown, AlertCircle } from 'lucide-react'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { cn } from '@/lib/utils'
import type { Property } from '@/lib/supabase/types'

interface Valuation {
  id: string
  estimated_value: number
  currency: string | null
  valuation_date: string
  created_at: string
}

interface Expense {
  id: string
  title: string
  amount: number
  currency: string | null
  category: string | null
  created_at: string
  date: string
}

interface RoiPageProps {
  property: Property
  initialValuations: Valuation[]
  initialExpenses: Expense[]
}

function fmtMoney(v: number) {
  return `€${v.toLocaleString('en', { maximumFractionDigits: 0 })}`
}

function StatCard({
  label,
  value,
  trend,
  colorClass,
}: {
  label: string
  value: string
  trend?: 'up' | 'down'
  colorClass?: string
}) {
  return (
    <Card className="p-3 flex flex-col gap-1">
      <p className="text-xs text-muted-foreground">{label}</p>
      <div className="flex items-center gap-1">
        <p className={cn('text-base font-bold', colorClass)}>{value}</p>
        {trend === 'up' && <TrendingUp className="h-3.5 w-3.5 text-green-500" />}
        {trend === 'down' && <TrendingDown className="h-3.5 w-3.5 text-red-500" />}
      </div>
    </Card>
  )
}

export function RoiPage({ property, initialValuations, initialExpenses }: RoiPageProps) {
  const valuations = initialValuations
  const expenses = initialExpenses

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const purchasePrice: number | null = (property as any).purchase_price ?? null
  const latestValuation = valuations.at(-1)
  const currentValue = latestValuation?.estimated_value ?? null

  const totalExpenses = expenses.reduce((sum, e) => sum + e.amount, 0)
  const totalInvested = (purchasePrice ?? 0) + totalExpenses

  const roi =
    currentValue != null && totalInvested > 0
      ? ((currentValue - totalInvested) / totalInvested) * 100
      : null

  const netGain = currentValue != null ? currentValue - totalInvested : null

  // --- Investment breakdown by category ---
  const categoryMap = new Map<string, number>()
  if (purchasePrice != null) {
    categoryMap.set('Purchase price', purchasePrice)
  }
  for (const e of expenses) {
    const cat = e.category ?? 'Uncategorised'
    categoryMap.set(cat, (categoryMap.get(cat) ?? 0) + e.amount)
  }
  const categoryEntries = Array.from(categoryMap.entries()).sort((a, b) => b[1] - a[1])
  const breakdownTotal = categoryEntries.reduce((s, [, v]) => s + v, 0)

  // --- Year-by-year table ---
  const yearSet = new Set<number>()
  for (const e of expenses) {
    const y = new Date(e.date).getFullYear()
    if (!isNaN(y)) yearSet.add(y)
  }
  for (const v of valuations) {
    const y = new Date(v.valuation_date).getFullYear()
    if (!isNaN(y)) yearSet.add(y)
  }
  const years = Array.from(yearSet).sort()

  // Build year rows
  interface YearRow {
    year: number
    expensesAmt: number
    valuationAmt: number | null
  }
  const yearRows: YearRow[] = years.map((year) => {
    const expensesAmt = expenses
      .filter((e) => new Date(e.date).getFullYear() === year)
      .reduce((s, e) => s + e.amount, 0)

    // Find the latest valuation in that year
    const yearValuations = valuations.filter(
      (v) => new Date(v.valuation_date).getFullYear() === year,
    )
    const valuationAmt =
      yearValuations.length > 0
        ? yearValuations[yearValuations.length - 1]!.estimated_value
        : null

    return { year, expensesAmt, valuationAmt }
  })

  return (
    <>
      <PageHeader title="ROI Calculator" description={property.name} backHref="/property" />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Summary cards */}
        <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
          <StatCard
            label="Purchase price"
            value={purchasePrice != null ? fmtMoney(purchasePrice) : '—'}
          />
          <StatCard label="Total invested" value={fmtMoney(totalInvested)} />
          <StatCard
            label="Current value"
            value={currentValue != null ? fmtMoney(currentValue) : '—'}
          />
          <StatCard
            label="Total ROI"
            value={roi != null ? `${roi.toFixed(1)}%` : '—'}
            trend={roi != null ? (roi >= 0 ? 'up' : 'down') : undefined}
          />
          <StatCard
            label="Net gain / loss"
            value={netGain != null ? fmtMoney(netGain) : '—'}
            colorClass={
              netGain != null
                ? netGain >= 0
                  ? 'text-green-600 dark:text-green-400'
                  : 'text-red-600 dark:text-red-400'
                : undefined
            }
          />
        </div>

        {/* No valuation notice */}
        {currentValue == null && (
          <Card className="flex items-start gap-3 p-4">
            <AlertCircle className="h-4 w-4 mt-0.5 shrink-0 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">
              Add a property valuation to see ROI
            </p>
          </Card>
        )}

        {/* Investment breakdown by category */}
        {breakdownTotal > 0 && (
          <Card className="p-0 overflow-hidden">
            <div className="px-4 py-3 border-b border-border/30">
              <p className="text-sm font-medium">Investment breakdown</p>
            </div>
            <div className="divide-y divide-border/30">
              {categoryEntries.map(([cat, amt]) => {
                const pct = breakdownTotal > 0 ? (amt / breakdownTotal) * 100 : 0
                return (
                  <div key={cat} className="px-4 py-3 flex flex-col gap-1.5">
                    <div className="flex items-center justify-between">
                      <p className="text-sm capitalize">{cat}</p>
                      <div className="flex items-center gap-2 text-sm">
                        <span className="font-semibold">{fmtMoney(amt)}</span>
                        <span className="text-xs text-muted-foreground w-10 text-right">
                          {pct.toFixed(0)}%
                        </span>
                      </div>
                    </div>
                    <div className="h-1.5 rounded-full bg-muted overflow-hidden">
                      <div
                        className="h-full rounded-full bg-primary/60 transition-all"
                        style={{ width: `${pct}%` }}
                      />
                    </div>
                  </div>
                )
              })}
            </div>
          </Card>
        )}

        {/* Year-by-year table */}
        {yearRows.length > 0 && (
          <Card className="p-0 overflow-hidden">
            <div className="px-4 py-3 border-b border-border/30">
              <p className="text-sm font-medium">Year-by-year overview</p>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border/30 bg-muted/30">
                    <th className="px-4 py-2 text-left text-xs font-medium text-muted-foreground">
                      Year
                    </th>
                    <th className="px-4 py-2 text-right text-xs font-medium text-muted-foreground">
                      Expenses
                    </th>
                    <th className="px-4 py-2 text-right text-xs font-medium text-muted-foreground">
                      Valuation
                    </th>
                    <th className="px-4 py-2 text-right text-xs font-medium text-muted-foreground">
                      Cumulative value
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border/30">
                  {yearRows.map((row) => {
                    // Cumulative expenses up to and including this year
                    const cumulativeExpenses = expenses
                      .filter((e) => new Date(e.date).getFullYear() <= row.year)
                      .reduce((s, e) => s + e.amount, 0)
                    const cumulativeInvested = (purchasePrice ?? 0) + cumulativeExpenses
                    const cumulativeGain =
                      row.valuationAmt != null
                        ? row.valuationAmt - cumulativeInvested
                        : null

                    return (
                      <tr key={row.year}>
                        <td className="px-4 py-2 font-medium">{row.year}</td>
                        <td className="px-4 py-2 text-right text-muted-foreground">
                          {row.expensesAmt > 0 ? fmtMoney(row.expensesAmt) : '—'}
                        </td>
                        <td className="px-4 py-2 text-right">
                          {row.valuationAmt != null ? fmtMoney(row.valuationAmt) : '—'}
                        </td>
                        <td
                          className={cn(
                            'px-4 py-2 text-right font-medium',
                            cumulativeGain != null && cumulativeGain >= 0
                              ? 'text-green-600 dark:text-green-400'
                              : cumulativeGain != null
                                ? 'text-red-600 dark:text-red-400'
                                : '',
                          )}
                        >
                          {cumulativeGain != null
                            ? `${cumulativeGain >= 0 ? '+' : ''}${fmtMoney(cumulativeGain)}`
                            : '—'}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          </Card>
        )}

        {/* Disclaimer */}
        <p className="text-xs text-muted-foreground px-1">
          Note: amounts shown in EUR. Currency conversion not applied.
        </p>
      </div>
    </>
  )
}
