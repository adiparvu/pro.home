'use client'

import * as React from 'react'
import { TrendingUp, TrendingDown, Minus } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'

interface HealthScoreBreakdown {
  maintenance: number
  finances: number
  documents: number
  inventory: number
  warranties: number
}

interface HealthScoreData {
  score: number
  breakdown: HealthScoreBreakdown
  grade: 'A' | 'B' | 'C' | 'D' | 'F'
  trend: 'up' | 'stable' | 'down'
}

function gradeColor(grade: string): string {
  switch (grade) {
    case 'A': return 'hsl(152,70%,42%)'
    case 'B': return 'hsl(96,65%,42%)'
    case 'C': return 'hsl(45,80%,48%)'
    case 'D': return 'hsl(22,75%,48%)'
    default:  return 'hsl(0,70%,50%)'
  }
}

function scoreToColor(score: number): string {
  if (score >= 85) return 'hsl(152,70%,42%)'
  if (score >= 70) return 'hsl(96,65%,42%)'
  if (score >= 50) return 'hsl(45,80%,48%)'
  if (score >= 25) return 'hsl(22,75%,48%)'
  return 'hsl(0,70%,50%)'
}

const BREAKDOWN_CONFIG: { key: keyof HealthScoreBreakdown; label: string; max: number }[] = [
  { key: 'maintenance', label: 'Maintenance', max: 30 },
  { key: 'finances',    label: 'Finances',    max: 25 },
  { key: 'documents',   label: 'Documents',   max: 20 },
  { key: 'inventory',   label: 'Inventory',   max: 15 },
  { key: 'warranties',  label: 'Warranties',  max: 10 },
]

function ScoreRing({ score, color }: { score: number; color: string }) {
  const size = 80
  const strokeWidth = 7
  const r = (size - strokeWidth) / 2
  const circumference = 2 * Math.PI * r
  const offset = circumference * (1 - score / 100)
  const center = size / 2

  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-label={`Health score ${score}`}>
      <circle cx={center} cy={center} r={r} fill="none" stroke="rgba(255,255,255,0.06)" strokeWidth={strokeWidth} />
      <circle
        cx={center} cy={center} r={r}
        fill="none"
        stroke={color}
        strokeWidth={strokeWidth}
        strokeDasharray={circumference}
        strokeDashoffset={offset}
        strokeLinecap="round"
        transform={`rotate(-90 ${center} ${center})`}
        style={{ transition: 'stroke-dashoffset 0.8s ease-out' }}
      />
      <text
        x={center} y={center + 6}
        textAnchor="middle"
        fill={color}
        fontSize={18}
        fontWeight="700"
        fontFamily="-apple-system, BlinkMacSystemFont, 'Inter', sans-serif"
      >
        {score}
      </text>
    </svg>
  )
}

export function HealthScoreCard() {
  const [data, setData] = React.useState<HealthScoreData | null>(null)
  const [loading, setLoading] = React.useState(true)

  React.useEffect(() => {
    fetch('/api/health-score')
      .then((r) => r.json() as Promise<HealthScoreData>)
      .then((d) => { if (d.score != null) setData(d) })
      .catch(() => null)
      .finally(() => setLoading(false))
  }, [])

  if (loading) {
    return (
      <Card variant="default" padding="md" className="animate-pulse">
        <div className="flex items-center gap-4">
          <div className="h-20 w-20 rounded-full bg-muted/20 shrink-0" />
          <div className="flex-1 space-y-2">
            <div className="h-3 w-24 rounded bg-muted/20" />
            <div className="h-4 w-16 rounded bg-muted/20" />
            <div className="h-3 w-32 rounded bg-muted/20" />
          </div>
        </div>
      </Card>
    )
  }

  if (!data) return null

  const color = scoreToColor(data.score)
  const gradeCol = gradeColor(data.grade)

  return (
    <Card variant="default" padding="md">
      <div className="flex items-center gap-4">
        <div className="shrink-0">
          <ScoreRing score={data.score} color={color} />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <p className="text-sm font-semibold text-foreground">Health Score</p>
            <span
              className="inline-flex items-center rounded-md px-1.5 py-0.5 text-xs font-bold"
              style={{ color: gradeCol, background: gradeCol + '22' }}
            >
              {data.grade}
            </span>
            {data.trend === 'up' && <TrendingUp className="h-3.5 w-3.5 text-[hsl(152,65%,48%)]" />}
            {data.trend === 'down' && <TrendingDown className="h-3.5 w-3.5 text-destructive" />}
            {data.trend === 'stable' && <Minus className="h-3.5 w-3.5 text-muted-foreground" />}
          </div>

          {/* Breakdown bars */}
          <div className="space-y-1.5 mt-2">
            {BREAKDOWN_CONFIG.map(({ key, label, max }) => {
              const val = data.breakdown[key]
              const pct = max > 0 ? (val / max) * 100 : 0
              const barColor = scoreToColor(pct)
              return (
                <div key={key}>
                  <div className="flex items-center justify-between mb-0.5">
                    <span className="text-[10px] text-muted-foreground">{label}</span>
                    <span className="text-[10px] tabular-nums text-muted-foreground">{val}/{max}</span>
                  </div>
                  <div className="h-1 rounded-full bg-[rgba(255,255,255,0.06)] overflow-hidden">
                    <div
                      className="h-full rounded-full"
                      style={{ width: `${pct}%`, background: barColor, transition: 'width 0.6s ease-out' }}
                    />
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      </div>
    </Card>
  )
}
