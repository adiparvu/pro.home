'use client'

import * as React from 'react'
import { Leaf, Settings, X, Loader2 } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { toast } from '@/hooks/use-toast'
import type { Property } from '@/lib/supabase/types'

interface MeterReading {
  id: string
  meter_type: string
  value: number
  unit: string | null
  reading_date: string
  created_at: string
}

interface CarbonSettings {
  property_id?: string
  electricity_factor: number
  gas_factor: number
  water_factor: number
  area_sqm: number | null
  occupants: number
}

interface CarbonPageProps {
  property: Property
  initialReadings: MeterReading[]
  initialSettings: CarbonSettings
}

interface MonthlyConsumption {
  yearMonth: string
  year: number
  month: number
  type: string
  consumption: number
  date: string
}

function calcMonthlyConsumption(readings: MeterReading[]): MonthlyConsumption[] {
  if (readings.length < 2) return []

  // Sort ascending by date
  const sorted = [...readings].sort(
    (a, b) => new Date(a.reading_date).getTime() - new Date(b.reading_date).getTime()
  )

  // Group by meter_type
  const byType: Record<string, MeterReading[]> = {}
  for (const r of sorted) {
    if (!byType[r.meter_type]) byType[r.meter_type] = []
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    byType[r.meter_type]!.push(r)
  }

  const results: MonthlyConsumption[] = []

  for (const [type, typeReadings] of Object.entries(byType)) {
    if (typeReadings.length < 2) continue
    for (let i = 1; i < typeReadings.length; i++) {
      const prev = typeReadings[i - 1]!
      const curr = typeReadings[i]!
      const diff = curr.value - prev.value
      if (diff < 0) continue // skip meter resets
      const d = new Date(curr.reading_date)
      const year = d.getFullYear()
      const month = d.getMonth() + 1
      const yearMonth = `${year}-${String(month).padStart(2, '0')}`
      results.push({ yearMonth, year, month, type, consumption: diff, date: curr.reading_date })
    }
  }

  return results
}

const MONTH_LABELS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

export function CarbonPage({ property, initialReadings, initialSettings }: CarbonPageProps) {
  const [settings, setSettings] = React.useState<CarbonSettings>(initialSettings)
  const [showSettings, setShowSettings] = React.useState(false)
  const [saving, setSaving] = React.useState(false)

  // Settings form state
  const [electricityFactor, setElectricityFactor] = React.useState(String(initialSettings.electricity_factor))
  const [gasFactor, setGasFactor] = React.useState(String(initialSettings.gas_factor))
  const [waterFactor, setWaterFactor] = React.useState(String(initialSettings.water_factor))
  const [areaSqm, setAreaSqm] = React.useState(initialSettings.area_sqm != null ? String(initialSettings.area_sqm) : '')
  const [occupants, setOccupants] = React.useState(String(initialSettings.occupants))

  // Sync form fields when settings change externally
  React.useEffect(() => {
    setElectricityFactor(String(settings.electricity_factor))
    setGasFactor(String(settings.gas_factor))
    setWaterFactor(String(settings.water_factor))
    setAreaSqm(settings.area_sqm != null ? String(settings.area_sqm) : '')
    setOccupants(String(settings.occupants))
  }, [settings])

  const monthly = React.useMemo(() => calcMonthlyConsumption(initialReadings), [initialReadings])

  const now = new Date()
  const thisYear = now.getFullYear()
  const thisMonthStr = `${thisYear}-${String(now.getMonth() + 1).padStart(2, '0')}`
  const lastYear = thisYear - 1

  // CO2 per monthly entry
  const monthlyCO2 = React.useMemo(() => {
    return monthly.map((entry) => {
      let factor = 0
      if (entry.type === 'electricity') factor = settings.electricity_factor
      else if (entry.type === 'gas') factor = settings.gas_factor
      else if (entry.type === 'water') factor = settings.water_factor
      return { ...entry, co2: entry.consumption * factor }
    })
  }, [monthly, settings])

  const thisMonthCO2 = monthlyCO2
    .filter((e) => e.yearMonth === thisMonthStr)
    .reduce((s, e) => s + e.co2, 0)

  const thisYearCO2 = monthlyCO2
    .filter((e) => e.year === thisYear)
    .reduce((s, e) => s + e.co2, 0)

  const lastYearCO2 = monthlyCO2
    .filter((e) => e.year === lastYear)
    .reduce((s, e) => s + e.co2, 0)

  const vsLastYear = lastYearCO2 > 0
    ? ((thisYearCO2 - lastYearCO2) / lastYearCO2) * 100
    : null

  // Per-meter type totals for this year
  const electricityThisYear = monthlyCO2
    .filter((e) => e.year === thisYear && e.type === 'electricity')
    .reduce((s, e) => s + e.co2, 0)
  const gasThisYear = monthlyCO2
    .filter((e) => e.year === thisYear && e.type === 'gas')
    .reduce((s, e) => s + e.co2, 0)
  const waterThisYear = monthlyCO2
    .filter((e) => e.year === thisYear && e.type === 'water')
    .reduce((s, e) => s + e.co2, 0)

  // Last 12 months bar chart
  const last12Months = React.useMemo(() => {
    const months: { label: string; yearMonth: string; value: number }[] = []
    for (let i = 11; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1)
      const ym = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
      const label = MONTH_LABELS[d.getMonth()] ?? ''
      const value = monthlyCO2
        .filter((e) => e.yearMonth === ym)
        .reduce((s, e) => s + e.co2, 0)
      months.push({ label, yearMonth: ym, value })
    }
    return months
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [monthlyCO2])

  const maxBarVal = Math.max(0.01, ...last12Months.map((m) => m.value))

  // Equivalencies
  const trees = thisYearCO2 / 21
  const carKm = thisYearCO2 / 0.17
  const flights = thisYearCO2 / 900

  const hasReadings = initialReadings.length > 0

  async function handleSaveSettings() {
    setSaving(true)
    try {
      const newSettings: CarbonSettings = {
        property_id: property.id,
        electricity_factor: parseFloat(electricityFactor) || 0.233,
        gas_factor: parseFloat(gasFactor) || 2.04,
        water_factor: parseFloat(waterFactor) || 0.001,
        area_sqm: areaSqm !== '' ? parseFloat(areaSqm) : null,
        occupants: parseInt(occupants) || 1,
      }
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { error } = await (supabase as any)
        .from('carbon_settings')
        .upsert(newSettings, { onConflict: 'property_id' })
      if (error) throw error
      setSettings(newSettings)
      setShowSettings(false)
      toast({ title: 'Settings saved', description: 'Carbon factors updated.' })
    } catch {
      toast({ title: 'Error', description: 'Failed to save settings.', variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  return (
    <>
      <PageHeader
        title="Carbon Footprint"
        description={property.name}
        action={{ label: 'Settings', href: '#', onClick: () => setShowSettings(true) }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6">
        {!hasReadings ? (
          <Card className="p-8 text-center">
            <Leaf className="mx-auto mb-3 h-10 w-10 text-muted-foreground" />
            <p className="text-sm font-medium text-foreground">No meter readings found</p>
            <p className="mt-1 text-xs text-muted-foreground">
              Add meter readings to see carbon footprint estimates.
            </p>
          </Card>
        ) : (
          <>
            {/* Summary cards */}
            <div className="grid grid-cols-3 gap-3">
              <Card className="p-3">
                <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">This month</p>
                <p className="mt-1 text-lg font-bold text-foreground">{thisMonthCO2.toFixed(1)}</p>
                <p className="text-[10px] text-muted-foreground">kg CO₂</p>
              </Card>
              <Card className="p-3">
                <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">This year</p>
                <p className="mt-1 text-lg font-bold text-foreground">{(thisYearCO2 / 1000).toFixed(2)}</p>
                <p className="text-[10px] text-muted-foreground">t CO₂</p>
              </Card>
              <Card className="p-3">
                <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">vs Last year</p>
                {vsLastYear !== null ? (
                  <>
                    <p
                      className={`mt-1 text-lg font-bold ${vsLastYear > 0 ? 'text-red-500' : 'text-green-500'}`}
                    >
                      {vsLastYear > 0 ? '+' : ''}{vsLastYear.toFixed(1)}%
                    </p>
                    <p className="text-[10px] text-muted-foreground">
                      {vsLastYear > 0 ? 'worse' : 'better'}
                    </p>
                  </>
                ) : (
                  <p className="mt-1 text-sm text-muted-foreground">—</p>
                )}
              </Card>
            </div>

            {/* Per-meter breakdown */}
            <Card className="p-4">
              <p className="mb-3 text-sm font-semibold text-foreground">This year by source</p>
              <div className="flex flex-col gap-2">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <span className="h-2.5 w-2.5 rounded-full bg-yellow-400" />
                    <span className="text-sm text-foreground">Electricity</span>
                  </div>
                  <span className="text-sm font-medium text-foreground">{electricityThisYear.toFixed(1)} kg</span>
                </div>
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <span className="h-2.5 w-2.5 rounded-full bg-orange-400" />
                    <span className="text-sm text-foreground">Gas</span>
                  </div>
                  <span className="text-sm font-medium text-foreground">{gasThisYear.toFixed(1)} kg</span>
                </div>
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <span className="h-2.5 w-2.5 rounded-full bg-blue-400" />
                    <span className="text-sm text-foreground">Water</span>
                  </div>
                  <span className="text-sm font-medium text-foreground">{waterThisYear.toFixed(1)} kg</span>
                </div>
              </div>
            </Card>

            {/* Bar chart — last 12 months */}
            <Card className="p-4">
              <p className="mb-4 text-sm font-semibold text-foreground">Last 12 months</p>
              <div className="flex h-32 items-end gap-1">
                {last12Months.map((m) => (
                  <div key={m.yearMonth} className="flex flex-1 flex-col items-center gap-1">
                    <div className="flex w-full flex-1 items-end">
                      <div
                        className="w-full rounded-t-sm transition-all"
                        style={{
                          height: `${Math.max(2, (m.value / maxBarVal) * 100)}%`,
                          background: 'hsl(152, 62%, 38%)',
                          opacity: m.value === 0 ? 0.2 : 1,
                        }}
                      />
                    </div>
                    <span className="text-[9px] text-muted-foreground">{m.label}</span>
                  </div>
                ))}
              </div>
            </Card>

            {/* Equivalencies */}
            <Card className="p-4">
              <div className="mb-3 flex items-center gap-2">
                <Leaf className="h-4 w-4 text-green-500" />
                <p className="text-sm font-semibold text-foreground">This year equals…</p>
              </div>
              <div className="flex flex-col gap-2">
                <div className="flex items-center justify-between rounded-lg bg-muted/40 px-3 py-2">
                  <span className="text-sm text-muted-foreground">Trees needed to offset/year</span>
                  <span className="text-sm font-semibold text-foreground">≈ {trees.toFixed(0)}</span>
                </div>
                <div className="flex items-center justify-between rounded-lg bg-muted/40 px-3 py-2">
                  <span className="text-sm text-muted-foreground">Car kilometres driven</span>
                  <span className="text-sm font-semibold text-foreground">≈ {(carKm / 1000).toFixed(0)}k km</span>
                </div>
                <div className="flex items-center justify-between rounded-lg bg-muted/40 px-3 py-2">
                  <span className="text-sm text-muted-foreground">Flights London–NYC</span>
                  <span className="text-sm font-semibold text-foreground">≈ {flights.toFixed(1)}</span>
                </div>
              </div>
            </Card>

            {/* Per-m² section */}
            {settings.area_sqm && settings.area_sqm > 0 && (
              <Card className="p-4">
                <p className="text-sm font-semibold text-foreground">Intensity</p>
                <div className="mt-2 flex items-center justify-between">
                  <span className="text-sm text-muted-foreground">kg CO₂ per m² per year</span>
                  <span className="text-sm font-semibold text-foreground">
                    {(thisYearCO2 / settings.area_sqm).toFixed(1)} kg/m²
                  </span>
                </div>
                {settings.occupants > 0 && (
                  <div className="mt-1 flex items-center justify-between">
                    <span className="text-sm text-muted-foreground">kg CO₂ per person per year</span>
                    <span className="text-sm font-semibold text-foreground">
                      {(thisYearCO2 / settings.occupants).toFixed(1)} kg
                    </span>
                  </div>
                )}
              </Card>
            )}
          </>
        )}
      </div>

      {/* Settings modal */}
      {showSettings && (
        <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50 p-4 sm:items-center">
          <div className="w-full max-w-md rounded-2xl bg-background p-6 shadow-xl">
            <div className="mb-4 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Settings className="h-5 w-5 text-muted-foreground" />
                <h2 className="text-base font-semibold text-foreground">Carbon Settings</h2>
              </div>
              <button
                type="button"
                onClick={() => setShowSettings(false)}
                className="flex h-8 w-8 items-center justify-center rounded-full glass-light text-muted-foreground hover:text-foreground transition-colors"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <div className="flex flex-col gap-4">
              <div>
                <label className="mb-1 block text-xs font-medium text-muted-foreground">
                  Electricity factor (kg CO₂ / kWh)
                </label>
                <Input
                  type="number"
                  step="0.001"
                  min="0"
                  value={electricityFactor}
                  onChange={(e) => setElectricityFactor(e.target.value)}
                  placeholder="0.233"
                />
              </div>
              <div>
                <label className="mb-1 block text-xs font-medium text-muted-foreground">
                  Gas factor (kg CO₂ / m³)
                </label>
                <Input
                  type="number"
                  step="0.01"
                  min="0"
                  value={gasFactor}
                  onChange={(e) => setGasFactor(e.target.value)}
                  placeholder="2.04"
                />
              </div>
              <div>
                <label className="mb-1 block text-xs font-medium text-muted-foreground">
                  Water factor (kg CO₂ / m³)
                </label>
                <Input
                  type="number"
                  step="0.0001"
                  min="0"
                  value={waterFactor}
                  onChange={(e) => setWaterFactor(e.target.value)}
                  placeholder="0.001"
                />
              </div>
              <div>
                <label className="mb-1 block text-xs font-medium text-muted-foreground">
                  Floor area (m²) — optional
                </label>
                <Input
                  type="number"
                  step="1"
                  min="0"
                  value={areaSqm}
                  onChange={(e) => setAreaSqm(e.target.value)}
                  placeholder="e.g. 85"
                />
              </div>
              <div>
                <label className="mb-1 block text-xs font-medium text-muted-foreground">
                  Occupants
                </label>
                <Input
                  type="number"
                  step="1"
                  min="1"
                  value={occupants}
                  onChange={(e) => setOccupants(e.target.value)}
                  placeholder="1"
                />
              </div>
            </div>

            <div className="mt-5 flex gap-3">
              <Button
                variant="outline"
                className="flex-1"
                onClick={() => setShowSettings(false)}
                disabled={saving}
              >
                Cancel
              </Button>
              <Button
                className="flex-1"
                onClick={handleSaveSettings}
                disabled={saving}
              >
                {saving ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Saving…
                  </>
                ) : (
                  'Save'
                )}
              </Button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
