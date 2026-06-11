'use client'

import * as React from 'react'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { cn } from '@/lib/utils'
import type { Property } from '@/lib/supabase/types'

interface Vacancy {
  id: string
  start_date: string
  end_date: string | null
  expected_rent_loss: number | null
  currency: string | null
}

interface LeaseInfo {
  id: string
  monthly_rent: number
  currency: string | null
  status: string
}

interface OccupancyPageProps {
  property: Property
  initialVacancies: Vacancy[]
  initialLeases: LeaseInfo[]
}

function fmtMoney(v: number, currency?: string | null) {
  const sym = currency === 'USD' ? '$' : currency === 'GBP' ? '£' : '€'
  return `${sym}${v.toLocaleString('en', { maximumFractionDigits: 0 })}`
}

function isLeapYear(year: number) {
  return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0
}

function daysInYear(year: number) {
  return isLeapYear(year) ? 366 : 365
}

function clampToYear(date: Date, year: number): Date {
  const start = new Date(year, 0, 1)
  const end = new Date(year, 11, 31)
  if (date < start) return start
  if (date > end) return end
  return date
}

function vacancyDaysInYear(vacancy: Vacancy, year: number): number {
  const start = new Date(vacancy.start_date)
  const end = vacancy.end_date ? new Date(vacancy.end_date) : new Date()
  const yearStart = new Date(year, 0, 1)
  const yearEnd = new Date(year, 11, 31, 23, 59, 59)

  if (start > yearEnd || end < yearStart) return 0

  const clampedStart = clampToYear(start, year)
  const clampedEnd = clampToYear(end, year)

  const ms = clampedEnd.getTime() - clampedStart.getTime()
  return Math.max(0, Math.ceil(ms / (1000 * 60 * 60 * 24)) + 1)
}

function rentLossForVacancyInYear(
  vacancy: Vacancy,
  year: number,
  fallbackDailyRent: number,
): number {
  const days = vacancyDaysInYear(vacancy, year)
  if (vacancy.expected_rent_loss != null) {
    // Prorate expected_rent_loss to the days that fall in this year
    const totalDays = vacancy.end_date
      ? Math.max(
          1,
          Math.ceil(
            (new Date(vacancy.end_date).getTime() - new Date(vacancy.start_date).getTime()) /
              (1000 * 60 * 60 * 24),
          ) + 1,
        )
      : 30
    return (vacancy.expected_rent_loss / totalDays) * days
  }
  return fallbackDailyRent * days
}

interface YearStats {
  year: number
  vacancyDays: number
  occupancyPct: number
  rentLoss: number
  occupiedDays: number
}

function OccupancyRing({ pct }: { pct: number }) {
  const radius = 54
  const circumference = 2 * Math.PI * radius
  const offset = circumference - (pct / 100) * circumference
  const color =
    pct >= 90 ? '#22c55e' : pct >= 70 ? '#f59e0b' : '#ef4444'

  return (
    <svg width="140" height="140" viewBox="0 0 140 140" className="mx-auto">
      <circle
        cx="70"
        cy="70"
        r={radius}
        fill="none"
        stroke="currentColor"
        strokeWidth="12"
        className="text-muted/30"
      />
      <circle
        cx="70"
        cy="70"
        r={radius}
        fill="none"
        stroke={color}
        strokeWidth="12"
        strokeDasharray={circumference}
        strokeDashoffset={offset}
        strokeLinecap="round"
        transform="rotate(-90 70 70)"
        style={{ transition: 'stroke-dashoffset 0.6s ease' }}
      />
      <text
        x="70"
        y="66"
        textAnchor="middle"
        className="fill-foreground"
        style={{ fontSize: 22, fontWeight: 700 }}
      >
        {pct.toFixed(1)}%
      </text>
      <text
        x="70"
        y="84"
        textAnchor="middle"
        className="fill-muted-foreground"
        style={{ fontSize: 11 }}
      >
        Occupied
      </text>
    </svg>
  )
}

function MonthTimeline({
  year,
  vacancies,
}: {
  year: number
  vacancies: Vacancy[]
}) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ]

  return (
    <div className="grid grid-cols-6 gap-1 md:grid-cols-12">
      {months.map((month, idx) => {
        const monthStart = new Date(year, idx, 1)
        const monthEnd = new Date(year, idx + 1, 0, 23, 59, 59)
        const daysInMonth = monthEnd.getDate()

        let vacantDays = 0
        for (const v of vacancies) {
          const vStart = new Date(v.start_date)
          const vEnd = v.end_date ? new Date(v.end_date) : new Date()
          if (vStart > monthEnd || vEnd < monthStart) continue
          const overlapStart = vStart < monthStart ? monthStart : vStart
          const overlapEnd = vEnd > monthEnd ? monthEnd : vEnd
          vacantDays += Math.max(
            0,
            Math.ceil(
              (overlapEnd.getTime() - overlapStart.getTime()) / (1000 * 60 * 60 * 24),
            ) + 1,
          )
        }

        const vacantPct = Math.min(100, (vacantDays / daysInMonth) * 100)
        const isVacant = vacantPct > 50
        const isMixed = vacantPct > 0 && vacantPct <= 50

        return (
          <div key={month} className="flex flex-col items-center gap-1">
            <div
              className={cn(
                'h-8 w-full rounded-md',
                isVacant
                  ? 'bg-red-500/70'
                  : isMixed
                    ? 'bg-amber-400/70'
                    : 'bg-green-500/70',
              )}
              title={`${month}: ${Math.round(vacantPct)}% vacant`}
            />
            <span className="text-[10px] text-muted-foreground">{month}</span>
          </div>
        )
      })}
    </div>
  )
}

export function OccupancyPage({
  property,
  initialVacancies,
  initialLeases,
}: OccupancyPageProps) {
  const vacancies = initialVacancies
  const activeLeases = initialLeases.filter((l) => l.status === 'active')
  const dailyRent =
    activeLeases.length > 0
      ? activeLeases.reduce((s, l) => s + l.monthly_rent, 0) / 30
      : 0
  const currency = activeLeases[0]?.currency ?? null

  const currentYear = new Date().getFullYear()
  const years = [currentYear - 3, currentYear - 2, currentYear - 1, currentYear]
  const [selectedYear, setSelectedYear] = React.useState(currentYear)

  const yearStats: YearStats[] = years.map((year) => {
    const total = daysInYear(year)
    let vacDays = 0
    for (const v of vacancies) {
      vacDays += vacancyDaysInYear(v, year)
    }
    vacDays = Math.min(vacDays, total)
    const occupiedDays = total - vacDays
    const occupancyPct = (occupiedDays / total) * 100
    let rentLoss = 0
    for (const v of vacancies) {
      rentLoss += rentLossForVacancyInYear(v, year, dailyRent)
    }
    return { year, vacancyDays: vacDays, occupancyPct, rentLoss, occupiedDays }
  })

  const selected = yearStats.find((s) => s.year === selectedYear) ?? yearStats[yearStats.length - 1]!

  const yearVacancies = vacancies.filter((v) => {
    const start = new Date(v.start_date)
    const end = v.end_date ? new Date(v.end_date) : new Date()
    return start.getFullYear() <= selectedYear && end.getFullYear() >= selectedYear
  })

  return (
    <>
      <PageHeader title="Occupancy" description={property.name} />
      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Year selector */}
        <div className="flex gap-2 overflow-x-auto pb-1">
          {years.map((y) => (
            <button
              key={y}
              type="button"
              onClick={() => setSelectedYear(y)}
              className={cn(
                'rounded-full px-4 py-1.5 text-sm font-medium transition-colors shrink-0',
                selectedYear === y
                  ? 'bg-primary text-white'
                  : 'glass-light text-muted-foreground hover:text-foreground',
              )}
            >
              {y}
            </button>
          ))}
        </div>

        {/* Occupancy ring + stats */}
        <Card className="p-4 flex flex-col gap-4">
          <OccupancyRing pct={selected.occupancyPct} />
          <div className="grid grid-cols-3 gap-3">
            <div className="text-center">
              <p className="text-lg font-bold text-green-500">{selected.occupiedDays}</p>
              <p className="text-xs text-muted-foreground">Occupied days</p>
            </div>
            <div className="text-center">
              <p className="text-lg font-bold text-red-500">{selected.vacancyDays}</p>
              <p className="text-xs text-muted-foreground">Vacant days</p>
            </div>
            <div className="text-center">
              <p className="text-lg font-bold">
                {selected.rentLoss > 0 ? fmtMoney(selected.rentLoss, currency) : '—'}
              </p>
              <p className="text-xs text-muted-foreground">Est. rent loss</p>
            </div>
          </div>
        </Card>

        {/* Monthly timeline */}
        <Card className="p-4 flex flex-col gap-3">
          <p className="text-sm font-medium">Monthly overview — {selectedYear}</p>
          <MonthTimeline year={selectedYear} vacancies={vacancies} />
          <div className="flex gap-3 text-xs text-muted-foreground mt-1">
            <span className="flex items-center gap-1">
              <span className="inline-block h-2.5 w-2.5 rounded-sm bg-green-500/70" /> Occupied
            </span>
            <span className="flex items-center gap-1">
              <span className="inline-block h-2.5 w-2.5 rounded-sm bg-amber-400/70" /> Mixed
            </span>
            <span className="flex items-center gap-1">
              <span className="inline-block h-2.5 w-2.5 rounded-sm bg-red-500/70" /> Vacant
            </span>
          </div>
        </Card>

        {/* Vacancy list */}
        {yearVacancies.length > 0 && (
          <Card className="p-0 overflow-hidden">
            <div className="px-4 py-3 border-b border-border/30">
              <p className="text-sm font-medium">Vacancies in {selectedYear}</p>
            </div>
            <div className="divide-y divide-border/30">
              {yearVacancies.map((v) => {
                const start = new Date(v.start_date)
                const end = v.end_date ? new Date(v.end_date) : null
                const days = vacancyDaysInYear(v, selectedYear)
                return (
                  <div key={v.id} className="px-4 py-3 flex items-center justify-between">
                    <div>
                      <p className="text-sm font-medium">
                        {start.toLocaleDateString('en', { month: 'short', day: 'numeric' })}
                        {' — '}
                        {end
                          ? end.toLocaleDateString('en', { month: 'short', day: 'numeric' })
                          : 'ongoing'}
                      </p>
                      <p className="text-xs text-muted-foreground">{days} days in {selectedYear}</p>
                    </div>
                    {v.expected_rent_loss != null && (
                      <p className="text-sm font-semibold text-red-500">
                        -{fmtMoney(v.expected_rent_loss, v.currency)}
                      </p>
                    )}
                  </div>
                )
              })}
            </div>
          </Card>
        )}

        {yearVacancies.length === 0 && (
          <Card className="p-4 text-center">
            <p className="text-sm text-muted-foreground">No vacancies recorded for {selectedYear}</p>
          </Card>
        )}
      </div>
    </>
  )
}
