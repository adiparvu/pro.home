'use client'

import * as React from 'react'
import { Zap, TrendingDown, TrendingUp, Sun, Wind, Droplets } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'

// Placeholder data — will connect to real integrations in Phase 4
const MOCK_DATA = {
  currentUsage: 2.4,
  monthlyBudget: 120,
  monthlySpent: 87,
  savingsVsLastMonth: 12,
  solar: { active: false, production: 0 },
  tip: 'Your peak consumption is between 6–9 PM. Consider shifting heavy appliances to off-peak hours to save up to 18%.',
}

export function EnergyOverview() {
  const budgetPercent = Math.round((MOCK_DATA.monthlySpent / MOCK_DATA.monthlyBudget) * 100)
  const isOverBudget = budgetPercent > 100

  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
      {/* Live usage */}
      <div className="glass-standard rounded-2xl p-5">
        <div className="flex items-start justify-between">
          <div>
            <p className="text-xs text-muted-foreground uppercase tracking-wider">Live Usage</p>
            <div className="mt-1 flex items-end gap-1">
              <span className="text-4xl font-bold" style={{ color: 'hsl(152, 62%, 48%)' }}>
                {MOCK_DATA.currentUsage}
              </span>
              <span className="mb-1 text-lg text-muted-foreground">kW</span>
            </div>
          </div>
          <div className="flex h-12 w-12 items-center justify-center rounded-xl"
            style={{ background: 'hsl(152, 62%, 48% / 0.15)' }}>
            <Zap className="h-6 w-6" style={{ color: 'hsl(152, 62%, 48%)' }} />
          </div>
        </div>

        {/* Monthly progress */}
        <div className="mt-4">
          <div className="flex items-center justify-between mb-1">
            <span className="text-xs text-muted-foreground">Monthly budget</span>
            <span className="text-xs font-medium text-foreground">
              €{MOCK_DATA.monthlySpent} / €{MOCK_DATA.monthlyBudget}
            </span>
          </div>
          <div className="h-2 rounded-full bg-white/10 overflow-hidden">
            <div
              className="h-full rounded-full transition-all duration-500"
              style={{
                width: `${Math.min(budgetPercent, 100)}%`,
                background: isOverBudget ? 'hsl(0, 68%, 52%)' : 'hsl(152, 62%, 48%)',
              }}
            />
          </div>
          <div className="mt-1 flex items-center justify-between">
            <span className="text-[10px] text-muted-foreground">{budgetPercent}% used</span>
            <div className="flex items-center gap-1">
              <TrendingDown className="h-3 w-3 text-success" />
              <span className="text-[10px] text-success">
                €{MOCK_DATA.savingsVsLastMonth} vs last month
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Quick stats */}
      <div className="grid grid-cols-3 gap-3">
        <Card variant="default" padding="sm">
          <Sun className="h-4 w-4 text-muted-foreground mb-1" />
          <p className="text-lg font-bold text-muted-foreground">—</p>
          <p className="text-[10px] text-muted-foreground">Solar</p>
        </Card>
        <Card variant="default" padding="sm">
          <Wind className="h-4 w-4 text-muted-foreground mb-1" />
          <p className="text-lg font-bold text-foreground">18°C</p>
          <p className="text-[10px] text-muted-foreground">Outdoor</p>
        </Card>
        <Card variant="default" padding="sm">
          <Droplets className="h-4 w-4 text-muted-foreground mb-1" />
          <p className="text-lg font-bold text-foreground">62%</p>
          <p className="text-[10px] text-muted-foreground">Humidity</p>
        </Card>
      </div>

      {/* ARIA tip */}
      <Card variant="default" padding="md">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <span className="text-sm">✨</span>
            ARIA Insight
          </CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">{MOCK_DATA.tip}</p>
          <Badge variant="neutral" size="xs" className="mt-2">Energy optimization</Badge>
        </CardContent>
      </Card>

      {/* Integration notice */}
      <div className="rounded-xl border border-border/50 glass-light p-4 text-center">
        <p className="text-sm font-medium text-foreground">Smart Home Integration</p>
        <p className="mt-1 text-xs text-muted-foreground">
          Connect your smart meter, EV charger, or solar panels to unlock real-time data
        </p>
        <button
          type="button"
          disabled
          className="mt-3 rounded-full glass-standard px-4 py-1.5 text-xs text-muted-foreground cursor-not-allowed"
        >
          Connect Device (Phase 4)
        </button>
      </div>
    </div>
  )
}
