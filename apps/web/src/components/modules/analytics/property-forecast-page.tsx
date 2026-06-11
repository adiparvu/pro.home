'use client'

import * as React from 'react'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { cn } from '@/lib/utils'
import type { Property } from '@/lib/supabase/types'

interface Valuation {
  id: string
  estimated_value: number
  currency: string | null
  valuation_date: string
}

interface FinancialRecord {
  id: string
  title: string
  amount: number
  currency: string | null
  type: string
  category: string | null
  date: string
}

interface PropertyForecastPageProps {
  property: Property
  initialValuations: Valuation[]
  financialRecords: FinancialRecord[]
}

function fmtMoney(v: number) {
  if (Math.abs(v) >= 1_000_000) return `€${(v / 1_000_000).toFixed(2)}M`
  if (Math.abs(v) >= 1_000) return `€${(v / 1_000).toFixed(0)}k`
  return `€${v.toFixed(0)}`
}

interface ForecastRow {
  year: number
  propertyValue: number
  annualRent: number
  annualExpenses: number
  netIncome: number
  cumulativeGain: number
}

interface InputState {
  appreciationRate: string
  rentIncreaseRate: string
  expenseInflationRate: string
  monthlyRent: string
  annualExpenses: string
  propertyValue: string
}

function NumberInput({
  label,
  value,
  onChange,
  suffix,
  placeholder,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  suffix?: string
  placeholder?: string
}) {
  return (
    <div>
      <label className="text-xs text-muted-foreground block mb-1">{label}</label>
      <div className="relative">
        <input
          type="number"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={placeholder}
          className="w-full rounded-lg border border-border/50 bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40 pr-8"
        />
        {suffix && (
          <span className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-muted-foreground">
            {suffix}
          </span>
        )}
      </div>
    </div>
  )
}

function ForecastChart({ rows, initialValue }: { rows: ForecastRow[]; initialValue: number }) {
  const values = rows.map((r) => r.propertyValue)
  const allValues = [initialValue, ...values]
  const minV = Math.min(...allValues)
  const maxV = Math.max(...allValues)
  const range = maxV - minV || 1

  const W = 280
  const H = 120
  const PAD = 20

  const points = [
    { x: PAD, y: H - PAD - ((initialValue - minV) / range) * (H - 2 * PAD) },
    ...rows.map((r, i) => ({
      x: PAD + ((i + 1) / rows.length) * (W - 2 * PAD),
      y: H - PAD - ((r.propertyValue - minV) / range) * (H - 2 * PAD),
    })),
  ]

  const pathD = points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(' ')

  return (
    <svg
      width="100%"
      viewBox={`0 0 ${W} ${H}`}
      className="w-full"
      aria-label="Property value forecast chart"
    >
      <path d={pathD} fill="none" stroke="hsl(152,62%,38%)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
      {points.map((p, i) => (
        <circle key={i} cx={p.x} cy={p.y} r="4" fill="hsl(152,62%,38%)" />
      ))}
      {points.map((p, i) => (
        <text
          key={`lbl-${i}`}
          x={p.x}
          y={p.y - 8}
          textAnchor="middle"
          className="fill-muted-foreground"
          style={{ fontSize: 9 }}
        >
          {i === 0 ? 'Now' : `Y${i}`}
        </text>
      ))}
    </svg>
  )
}

export function PropertyForecastPage({
  property,
  initialValuations,
  financialRecords,
}: PropertyForecastPageProps) {
  const latestValuation = initialValuations.at(-1)
  const currentYear = new Date().getFullYear()

  // Compute last year's expense total
  const lastYearExpenses = financialRecords
    .filter(
      (r) =>
        r.type === 'expense' && new Date(r.date).getFullYear() === currentYear - 1,
    )
    .reduce((s, r) => s + r.amount, 0)

  // Try to find active lease from financial records (income type)
  const lastYearIncome = financialRecords
    .filter(
      (r) =>
        r.type === 'income' && new Date(r.date).getFullYear() === currentYear - 1,
    )
    .reduce((s, r) => s + r.amount, 0)
  const estimatedMonthlyRent = lastYearIncome > 0 ? Math.round(lastYearIncome / 12) : 0

  const [inputs, setInputs] = React.useState<InputState>({
    appreciationRate: '3',
    rentIncreaseRate: '2',
    expenseInflationRate: '3',
    monthlyRent: estimatedMonthlyRent.toString(),
    annualExpenses: Math.round(lastYearExpenses).toString(),
    propertyValue: (latestValuation?.estimated_value ?? 0).toString(),
  })

  function updateInput(key: keyof InputState) {
    return (v: string) => setInputs((prev) => ({ ...prev, [key]: v }))
  }

  const appreciationRate = parseFloat(inputs.appreciationRate) || 0
  const rentIncreaseRate = parseFloat(inputs.rentIncreaseRate) || 0
  const expenseInflationRate = parseFloat(inputs.expenseInflationRate) || 0
  const monthlyRent = parseFloat(inputs.monthlyRent) || 0
  const baseAnnualExpenses = parseFloat(inputs.annualExpenses) || 0
  const basePropertyValue = parseFloat(inputs.propertyValue) || 0

  const baseAnnualRent = monthlyRent * 12

  const rows: ForecastRow[] = []
  let cumulativeNetIncome = 0

  for (let year = 1; year <= 5; year++) {
    const propertyValue = basePropertyValue * Math.pow(1 + appreciationRate / 100, year)
    const annualRent = baseAnnualRent * Math.pow(1 + rentIncreaseRate / 100, year)
    const annualExpenses = baseAnnualExpenses * Math.pow(1 + expenseInflationRate / 100, year)
    const netIncome = annualRent - annualExpenses
    cumulativeNetIncome += netIncome
    const cumulativeGain = propertyValue - basePropertyValue + cumulativeNetIncome

    rows.push({
      year: currentYear + year,
      propertyValue,
      annualRent,
      annualExpenses,
      netIncome,
      cumulativeGain,
    })
  }

  return (
    <>
      <PageHeader title="5-Year Forecast" description={property.name} />
      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Assumptions */}
        <Card className="p-4 flex flex-col gap-3">
          <p className="text-sm font-medium">Assumptions</p>
          <div className="grid grid-cols-2 gap-3">
            <NumberInput
              label="Appreciation rate"
              value={inputs.appreciationRate}
              onChange={updateInput('appreciationRate')}
              suffix="%/yr"
            />
            <NumberInput
              label="Rent increase"
              value={inputs.rentIncreaseRate}
              onChange={updateInput('rentIncreaseRate')}
              suffix="%/yr"
            />
            <NumberInput
              label="Expense inflation"
              value={inputs.expenseInflationRate}
              onChange={updateInput('expenseInflationRate')}
              suffix="%/yr"
            />
            <NumberInput
              label="Monthly rent (€)"
              value={inputs.monthlyRent}
              onChange={updateInput('monthlyRent')}
              placeholder="0"
            />
            <NumberInput
              label="Annual expenses (€)"
              value={inputs.annualExpenses}
              onChange={updateInput('annualExpenses')}
              placeholder="0"
            />
            <NumberInput
              label="Property value (€)"
              value={inputs.propertyValue}
              onChange={updateInput('propertyValue')}
              placeholder="0"
            />
          </div>
        </Card>

        {/* Chart */}
        {basePropertyValue > 0 && (
          <Card className="p-4 flex flex-col gap-2">
            <p className="text-sm font-medium">Property value over 5 years</p>
            <ForecastChart rows={rows} initialValue={basePropertyValue} />
          </Card>
        )}

        {/* Table */}
        <Card className="p-0 overflow-hidden">
          <div className="px-4 py-3 border-b border-border/30">
            <p className="text-sm font-medium">Year-by-year projections</p>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border/30 bg-muted/30">
                  <th className="px-3 py-2 text-left text-xs font-medium text-muted-foreground">Year</th>
                  <th className="px-3 py-2 text-right text-xs font-medium text-muted-foreground">Property</th>
                  <th className="px-3 py-2 text-right text-xs font-medium text-muted-foreground">Rent</th>
                  <th className="px-3 py-2 text-right text-xs font-medium text-muted-foreground">Expenses</th>
                  <th className="px-3 py-2 text-right text-xs font-medium text-muted-foreground">Net</th>
                  <th className="px-3 py-2 text-right text-xs font-medium text-muted-foreground">Cum. Gain</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border/30">
                {rows.map((row) => (
                  <tr key={row.year}>
                    <td className="px-3 py-2 font-medium">{row.year}</td>
                    <td className="px-3 py-2 text-right">{fmtMoney(row.propertyValue)}</td>
                    <td className="px-3 py-2 text-right text-green-600 dark:text-green-400">{fmtMoney(row.annualRent)}</td>
                    <td className="px-3 py-2 text-right text-red-500">{fmtMoney(row.annualExpenses)}</td>
                    <td className={cn('px-3 py-2 text-right font-medium', row.netIncome >= 0 ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400')}>
                      {row.netIncome >= 0 ? '+' : ''}{fmtMoney(row.netIncome)}
                    </td>
                    <td className={cn('px-3 py-2 text-right font-semibold', row.cumulativeGain >= 0 ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400')}>
                      {row.cumulativeGain >= 0 ? '+' : ''}{fmtMoney(row.cumulativeGain)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>

        <p className="text-xs text-muted-foreground px-1">
          Projections are estimates based on the assumptions above. Actual results may vary.
          Amounts shown in EUR.
        </p>
      </div>
    </>
  )
}
