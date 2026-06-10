'use client'

import * as React from 'react'
import Link from 'next/link'
import { Archive, Plus, Search, Tag, AlertCircle, ChevronRight, TrendingUp, TrendingDown } from 'lucide-react'
import type { Property, InventoryItem } from '@/lib/supabase/types'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'

interface InventoryPageProps {
  property: Property
  items: InventoryItem[]
}

const CONDITION_VARIANTS = {
  excellent: 'excellent',
  good: 'good',
  fair: 'fair',
  poor: 'poor',
  broken: 'critical',
} as const

export function InventoryPage({ property, items }: InventoryPageProps) {
  const [search, setSearch] = React.useState('')
  const [categoryFilter, setCategoryFilter] = React.useState<string | null>(null)

  const categories = Array.from(new Set(items.map((i) => i.category).filter(Boolean)))

  const filtered = items.filter((item) => {
    const matchesSearch =
      !search ||
      item.name.toLowerCase().includes(search.toLowerCase()) ||
      (item.brand ?? '').toLowerCase().includes(search.toLowerCase())
    const matchesCategory = !categoryFilter || item.category === categoryFilter
    return matchesSearch && matchesCategory
  })

  const recallCount = items.filter((i) => i.recall_active).length

  // Portfolio value: current_value when available, else purchase_price as fallback
  const itemsWithValue = items.filter((i) => i.purchase_price != null || i.current_value != null)
  const totalOriginalCost = itemsWithValue.reduce((s, i) => s + (i.purchase_price ?? 0), 0)
  const totalCurrentValue = itemsWithValue.reduce((s, i) => s + (i.current_value ?? i.purchase_price ?? 0), 0)
  const portfolioGain = totalCurrentValue - totalOriginalCost

  return (
    <>
      <PageHeader
        title="Inventory"
        description={property.name}
        action={{ label: 'Add Item', href: '/inventory/new' }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[88px] md:pb-6">
        {/* Stats */}
        <div className="grid grid-cols-3 gap-3">
          <StatTile label="Total items" value={String(items.length)} />
          <StatTile
            label="Warranties"
            value={String(items.filter((i) => i.warranty_expires).length)}
          />
          <StatTile
            label="Recalls"
            value={String(recallCount)}
            alert={recallCount > 0}
          />
        </div>

        {/* Portfolio value */}
        {itemsWithValue.length > 0 && (
          <PortfolioCard
            currentValue={totalCurrentValue}
            originalCost={totalOriginalCost}
            gain={portfolioGain}
            itemCount={itemsWithValue.length}
          />
        )}

        {/* Recall banner */}
        {recallCount > 0 && (
          <div className="flex items-center gap-3 rounded-xl border border-destructive/30 bg-destructive/10 px-4 py-3">
            <AlertCircle className="h-4 w-4 text-destructive shrink-0" />
            <p className="text-sm text-destructive">
              {recallCount} item{recallCount > 1 ? 's have' : ' has'} an active recall notice
            </p>
          </div>
        )}

        {/* Search + filter */}
        <div className="flex flex-col gap-2">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <input
              type="search"
              placeholder="Search items..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="h-11 w-full rounded-xl border border-border glass-light pl-10 pr-4 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
            />
          </div>

          {categories.length > 0 && (
            <div className="flex gap-2 overflow-x-auto scrollbar-hide">
              <button
                type="button"
                onClick={() => setCategoryFilter(null)}
                className={`shrink-0 rounded-full px-3 py-1 text-xs font-medium transition-colors ${
                  !categoryFilter
                    ? 'bg-primary text-white'
                    : 'glass-light text-muted-foreground hover:text-foreground'
                }`}
              >
                All
              </button>
              {categories.map((cat) => (
                <button
                  key={cat}
                  type="button"
                  onClick={() => setCategoryFilter(categoryFilter === cat ? null : cat)}
                  className={`shrink-0 rounded-full px-3 py-1 text-xs font-medium capitalize transition-colors ${
                    categoryFilter === cat
                      ? 'bg-primary text-white'
                      : 'glass-light text-muted-foreground hover:text-foreground'
                  }`}
                >
                  {cat}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Items list */}
        {filtered.length === 0 ? (
          <EmptyState hasItems={items.length > 0} />
        ) : (
          <div className="flex flex-col gap-2">
            {filtered.map((item) => (
              <InventoryItemCard key={item.id} item={item} />
            ))}
          </div>
        )}
      </div>
    </>
  )
}

function PortfolioCard({
  currentValue,
  originalCost,
  gain,
  itemCount,
}: {
  currentValue: number
  originalCost: number
  gain: number
  itemCount: number
}) {
  const gainPct = originalCost > 0 ? (gain / originalCost) * 100 : 0
  const isGain = gain >= 0
  const fmt = (n: number) =>
    `€${Math.abs(n).toLocaleString('en-US', { maximumFractionDigits: 0 })}`

  return (
    <Card variant="default" padding="md">
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-1">
            Portfolio Value
          </p>
          <p className="text-2xl font-bold text-foreground">{fmt(currentValue)}</p>
          {originalCost > 0 && (
            <p className="text-xs text-muted-foreground mt-0.5">
              Original cost {fmt(originalCost)} · {itemCount} item{itemCount !== 1 ? 's' : ''}
            </p>
          )}
        </div>
        {originalCost > 0 && gain !== 0 && (
          <div
            className={`flex items-center gap-1 rounded-xl px-3 py-2 ${
              isGain ? 'bg-[hsl(152,62%,42%)]/15' : 'bg-destructive/15'
            }`}
          >
            {isGain
              ? <TrendingUp className="h-4 w-4 text-[hsl(152,62%,48%)]" />
              : <TrendingDown className="h-4 w-4 text-destructive" />
            }
            <div className="text-right">
              <p className={`text-sm font-bold ${isGain ? 'text-[hsl(152,62%,48%)]' : 'text-destructive'}`}>
                {isGain ? '+' : '-'}{fmt(gain)}
              </p>
              <p className={`text-[10px] ${isGain ? 'text-[hsl(152,62%,48%)]' : 'text-destructive'}`}>
                {isGain ? '+' : ''}{gainPct.toFixed(1)}%
              </p>
            </div>
          </div>
        )}
      </div>
    </Card>
  )
}

function StatTile({ label, value, alert }: { label: string; value: string; alert?: boolean }) {
  return (
    <Card variant="default" padding="sm">
      <p className={`text-xl font-bold ${alert ? 'text-destructive' : 'text-foreground'}`}>
        {value}
      </p>
      <p className="text-xs text-muted-foreground mt-0.5">{label}</p>
    </Card>
  )
}

function InventoryItemCard({ item }: { item: InventoryItem }) {
  return (
    <Link href={`/inventory/${item.id}`}>
    <Card variant="default" hover padding="md" className="group">
      <div className="flex items-start gap-3">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl glass-standard">
          <Archive className="h-5 w-5 text-muted-foreground" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <p className="text-sm font-medium text-foreground truncate">{item.name}</p>
            <div className="flex shrink-0 items-center gap-1.5">
              {item.recall_active && (
                <Badge variant="critical" size="xs">Recall</Badge>
              )}
              {item.condition && (
                <Badge
                  variant={CONDITION_VARIANTS[item.condition] ?? 'neutral'}
                  size="xs"
                >
                  {item.condition}
                </Badge>
              )}
            </div>
          </div>
          {(item.brand || item.model) && (
            <p className="text-xs text-muted-foreground">
              {[item.brand, item.model].filter(Boolean).join(' · ')}
            </p>
          )}
          <div className="mt-1 flex flex-wrap items-center gap-1.5">
            {item.category && (
              <span className="flex items-center gap-1 text-[10px] text-muted-foreground">
                <Tag className="h-2.5 w-2.5" />
                {item.category}
              </span>
            )}
            {item.warranty_expires && (
              <span className="text-[10px] text-muted-foreground">
                Warranty until {new Date(item.warranty_expires).getFullYear()}
              </span>
            )}
          </div>
        </div>
        <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5 mt-1" />
      </div>
    </Card>
    </Link>
  )
}

function EmptyState({ hasItems }: { hasItems: boolean }) {
  return (
    <div className="flex flex-col items-center gap-3 py-16 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-2xl glass-standard">
        <Archive className="h-7 w-7 text-muted-foreground" />
      </div>
      <p className="font-semibold text-foreground">
        {hasItems ? 'No items match your search' : 'No inventory yet'}
      </p>
      <p className="text-sm text-muted-foreground max-w-[200px]">
        {hasItems
          ? 'Try a different search term or category'
          : 'Start adding appliances, furniture, and other items'}
      </p>
    </div>
  )
}
