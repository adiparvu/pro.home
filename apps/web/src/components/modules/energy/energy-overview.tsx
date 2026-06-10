'use client'

import * as React from 'react'
import { Zap, TrendingDown, Sun, Wind, Droplets, Banknote } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'

interface EnergyOverviewProps {
  ytdUtilities: number
  monthlyUtilities: number
  currency: string
  hasRealData: boolean
}

const ARIA_TIP = 'Your peak consumption is typically between 6–9 PM. Consider shifting heavy appliances (dishwasher, washing machine) to off-peak hours to reduce costs by up to 18%.'

export function EnergyOverview({ ytdUtilities, monthlyUtilities, currency, hasRealData }: EnergyOverviewProps) {
  const currencySymbol = currency === 'EUR' ? '€' : currency === 'USD' ? '$' : currency === 'GBP' ? '£' : currency

  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
      {/* Live usage placeholder */}
      <div className="glass-standard rounded-2xl p-5">
        <div className="flex items-start justify-between">
          <div>
            <p className="text-xs text-muted-foreground uppercase tracking-wider">Live Usage</p>
            <div className="mt-1 flex items-end gap-1">
              <span className="text-4xl font-bold" style={{ color: 'hsl(152, 62%, 48%)' }}>
                —
              </span>
              <span className="mb-1 text-lg text-muted-foreground">kW</span>
            </div>
            <p className="text-xs text-muted-foreground mt-1">Smart meter not connected</p>
          </div>
          <div
            className="flex h-12 w-12 items-center justify-center rounded-xl"
            style={{ background: 'hsl(152 62% 48% / 0.12)' }}
          >
            <Zap className="h-6 w-6" style={{ color: 'hsl(152, 62%, 48%)' }} />
          </div>
        </div>

        {/* Utility costs from financial records */}
        {hasRealData ? (
          <div className="mt-4 pt-4 border-t border-white/8">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-xs text-muted-foreground">This month</p>
                <p className="text-lg font-bold text-foreground mt-0.5">
                  {currencySymbol}{monthlyUtilities.toLocaleString()}
                </p>
                <p className="text-[10px] text-muted-foreground">Utility costs logged</p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">YTD utilities</p>
                <p className="text-lg font-bold text-foreground mt-0.5">
                  {currencySymbol}{ytdUtilities.toLocaleString()}
                </p>
                <p className="text-[10px] text-muted-foreground">from Finances module</p>
              </div>
            </div>
          </div>
        ) : (
          <div className="mt-4 pt-4 border-t border-white/8">
            <p className="text-xs text-muted-foreground">
              Log utility expenses in{' '}
              <a href="/finances" className="underline hover:text-foreground">Finances</a>
              {' '}to see cost tracking here.
            </p>
          </div>
        )}
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
          <p className="text-lg font-bold text-foreground">—</p>
          <p className="text-[10px] text-muted-foreground">Outdoor</p>
        </Card>
        <Card variant="default" padding="sm">
          <Droplets className="h-4 w-4 text-muted-foreground mb-1" />
          <p className="text-lg font-bold text-foreground">—</p>
          <p className="text-[10px] text-muted-foreground">Humidity</p>
        </Card>
      </div>

      {/* ARIA tip */}
      <Card variant="default" padding="md">
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-sm">
            <span>✨</span>
            ARIA Energy Tip
          </CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">{ARIA_TIP}</p>
          <Badge variant="neutral" size="xs" className="mt-2">Energy optimization</Badge>
        </CardContent>
      </Card>

      {/* Utility spending shortcut */}
      {hasRealData && (
        <Card variant="default" padding="md">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-[hsl(45,75%,42%)]/15">
              <Banknote className="h-5 w-5 text-[hsl(45,75%,42%)]" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-foreground">
                {currencySymbol}{ytdUtilities.toLocaleString()} in utilities this year
              </p>
              <p className="text-xs text-muted-foreground">Logged across {new Date().getFullYear()} so far</p>
            </div>
            <a
              href="/finances"
              className="shrink-0 text-xs font-medium text-primary hover:text-primary/80 transition-colors"
            >
              View all
            </a>
          </div>
        </Card>
      )}

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
