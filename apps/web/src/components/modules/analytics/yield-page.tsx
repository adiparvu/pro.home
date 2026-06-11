'use client'

import * as React from 'react'
import { AlertCircle } from 'lucide-react'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { cn } from '@/lib/utils'
import type { Property } from '@/lib/supabase/types'

interface LeaseInfo {
  id: string
  monthly_rent: number
  currency: string | null
  status: string
  start_date: string | null
  end_date: string | null
}

interface Valuation {
  id: string
  estimated_value: number
  currency: string | null
  valuation_date: string
}

interface ExpenseRecord {
  id: string
  title: string
  amount: number
  currency: string | null
  category: string | null
  date: string
}

interface YieldPageProps {
  property: Property
  initialLeases: LeaseInfo[]
  latestValuation: Valuation | null
  annualExpenses: ExpenseRecord[]
}

function fmtMoney(v: number) {
  return `€${v.toLocaleString('en', { maximumFractionDigits: 0 })}`
}

function yieldColor(pct: number) {
  if (pct >= 5) return 'text-green-600 dark:text-green-400'
  if (pct >= 3) return 'text-amber-600 dark:text-amber-400'
  return 'text-red-600 dark:text-red-400'
}

function StatCard({
  label,
  value,
  colorClass,
  sub,
}: {
  label: string
  value: string
  colorClass?: string
  sub?: string
}) {
  return (
    <Card className="p-4 flex flex-col gap-1">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className={cn('text-xl font-bold', colorClass)}>{value}</p>
      {sub && <p className="text-xs text-muted-foreground">{sub}</p>}
    </Card>
  )
}

export function YieldPage({
  property,
  initialLeases,
  latestValuation,
  annualExpenses,
}: YieldPageProps) {
  const activeLeases = initialLeases.filter((l) => l.status === 'active')
  const annualGrossRentDefault = activeLeases.reduce((s, l) => s + l.monthly_rent * 12, 0)
  const annualExpensesDefault = annualExpenses.reduce((s, e) => s + e.amount, 0)
  const propertyValueDefault = latestValuation?.estimated_value ?? 0

  const [propertyValue, setPropertyValue] = React.useState(propertyValueDefault.toString())
  const [annualExpensesInput, setAnnualExpensesInput] = React.useState(
    Math.round(annualExpensesDefault).toString(),
  )

  const propVal = parseFloat(propertyValue.replace(/,/g, '')) || 0
  const annExp = parseFloat(annualExpensesInput.replace(/,/g, '')) || 0

  const grossYield = propVal > 0 ? (annualGrossRentDefault / propVal) * 100 : 0
  const netAnnualIncome = annualGrossRentDefault - annExp
  const netYield = propVal > 0 ? (netAnnualIncome / propVal) * 100 : 0
  const monthlyCashFlow = netAnnualIncome / 12

  return (
    <>
      <PageHeader title="Rent Yield" description={property.name} />
      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {activeLeases.length === 0 && (
          <Card className="flex items-start gap-3 p-4">
            <AlertCircle className="h-4 w-4 mt-0.5 shrink-0 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">
              No active leases found. Add a lease to calculate rent yield.
            </p>
          </Card>
        )}

        {/* Stat cards */}
        <div className="grid grid-cols-2 gap-3">
          <StatCard
            label="Gross Yield"
            value={propVal > 0 ? `${grossYield.toFixed(2)}%` : '—'}
            colorClass={propVal > 0 ? yieldColor(grossYield) : undefined}
            sub="Annual rent / property value"
          />
          <StatCard
            label="Net Yield"
            value={propVal > 0 ? `${netYield.toFixed(2)}%` : '—'}
            colorClass={propVal > 0 ? yieldColor(netYield) : undefined}
            sub="After expenses"
          />
          <StatCard
            label="Annual Net Income"
            value={fmtMoney(netAnnualIncome)}
            colorClass={netAnnualIncome >= 0 ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}
          />
          <StatCard
            label="Monthly Cash Flow"
            value={fmtMoney(monthlyCashFlow)}
            colorClass={monthlyCashFlow >= 0 ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}
          />
        </div>

        {/* Editable inputs */}
        <Card className="p-4 flex flex-col gap-4">
          <p className="text-sm font-medium">Assumptions</p>
          <div className="flex flex-col gap-3">
            <div>
              <label className="text-xs text-muted-foreground block mb-1">
                Property value (€)
              </label>
              <input
                type="number"
                value={propertyValue}
                onChange={(e) => setPropertyValue(e.target.value)}
                className="w-full rounded-lg border border-border/50 bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40"
                placeholder="Enter property value"
              />
              {latestValuation && (
                <p className="text-xs text-muted-foreground mt-1">
                  Latest valuation: {fmtMoney(latestValuation.estimated_value)} ({latestValuation.valuation_date})
                </p>
              )}
            </div>
            <div>
              <label className="text-xs text-muted-foreground block mb-1">
                Annual expenses (€)
              </label>
              <input
                type="number"
                value={annualExpensesInput}
                onChange={(e) => setAnnualExpensesInput(e.target.value)}
                className="w-full rounded-lg border border-border/50 bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40"
                placeholder="Enter annual expenses"
              />
              <p className="text-xs text-muted-foreground mt-1">
                Based on last 12 months: {fmtMoney(annualExpensesDefault)}
              </p>
            </div>
          </div>
        </Card>

        {/* Breakdown table */}
        <Card className="p-0 overflow-hidden">
          <div className="px-4 py-3 border-b border-border/30">
            <p className="text-sm font-medium">Income breakdown</p>
          </div>
          <div className="divide-y divide-border/30">
            <div className="flex items-center justify-between px-4 py-3">
              <p className="text-sm text-muted-foreground">Annual gross rent</p>
              <p className="text-sm font-semibold">{fmtMoney(annualGrossRentDefault)}</p>
            </div>
            <div className="flex items-center justify-between px-4 py-3">
              <p className="text-sm text-muted-foreground">Annual expenses</p>
              <p className="text-sm font-semibold text-red-500">-{fmtMoney(annExp)}</p>
            </div>
            <div className="flex items-center justify-between px-4 py-3 bg-muted/20">
              <p className="text-sm font-medium">Net annual income</p>
              <p className={cn('text-sm font-bold', netAnnualIncome >= 0 ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400')}>
                {fmtMoney(netAnnualIncome)}
              </p>
            </div>
          </div>
        </Card>

        {/* Active leases */}
        {activeLeases.length > 0 && (
          <Card className="p-0 overflow-hidden">
            <div className="px-4 py-3 border-b border-border/30">
              <p className="text-sm font-medium">Active leases</p>
            </div>
            <div className="divide-y divide-border/30">
              {activeLeases.map((lease) => (
                <div key={lease.id} className="flex items-center justify-between px-4 py-3">
                  <p className="text-sm text-muted-foreground">Lease {lease.id.slice(0, 8)}</p>
                  <p className="text-sm font-semibold">{fmtMoney(lease.monthly_rent)}/mo</p>
                </div>
              ))}
            </div>
          </Card>
        )}

        <p className="text-xs text-muted-foreground px-1">
          Industry benchmark: 5–8% gross yield for residential properties. Amounts shown in EUR.
        </p>
      </div>
    </>
  )
}
