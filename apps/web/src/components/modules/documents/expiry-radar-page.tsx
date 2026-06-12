'use client'

import * as React from 'react'
import Link from 'next/link'
import { FileText, ShieldCheck, FileSignature, ScanSearch, ChevronRight } from 'lucide-react'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { cn } from '@/lib/utils'
import type { Property } from '@/lib/supabase/types'

interface DocItem {
  id: string
  name: string
  category: string | null
  expires_at: string
  type: 'document' | 'warranty' | 'lease'
  href: string
}

interface RawDocument {
  id: string
  name: string
  category: string | null
  expires_at: string | null
}

interface RawInventoryItem {
  id: string
  name: string
  category: string | null
  warranty_expires: string | null
}

interface RawLease {
  id: string
  tenant_name: string | null
  status: string | null
  end_date: string | null
}

interface ExpiryRadarPageProps {
  property: Property
  documents: RawDocument[]
  inventoryItems: RawInventoryItem[]
  leases: RawLease[]
}

function Section({
  title,
  items,
  color,
  emptyText,
}: {
  title: string
  items: DocItem[]
  color: string
  bgColor: string
  emptyText: string
}) {
  return (
    <div>
      <div className="flex items-center gap-2 mb-2">
        <div className="h-2 w-2 rounded-full" style={{ background: color }} />
        <p className="text-sm font-semibold" style={{ color }}>{title}</p>
        <span className="text-xs text-muted-foreground">({items.length})</span>
      </div>
      {items.length === 0 ? (
        <p className="text-xs text-muted-foreground py-2 pl-4">{emptyText}</p>
      ) : (
        <Card className="p-0 overflow-hidden">
          <div className="divide-y divide-border/30">
            {items.map((item) => (
              <ExpiryRow key={`${item.type}-${item.id}`} item={item} />
            ))}
          </div>
        </Card>
      )}
    </div>
  )
}

function ExpiryRow({ item }: { item: DocItem }) {
  const daysUntil = Math.round(
    (new Date(item.expires_at).getTime() - Date.now()) / 86400000
  )
  const Icon =
    item.type === 'document'
      ? FileText
      : item.type === 'warranty'
      ? ShieldCheck
      : FileSignature

  const dateLabel =
    daysUntil < 0
      ? `${Math.abs(daysUntil)} days ago`
      : daysUntil === 0
      ? 'Today'
      : `${daysUntil} days`

  const dateColor =
    daysUntil < 0
      ? 'text-destructive'
      : daysUntil <= 30
      ? 'text-[hsl(45,75%,42%)]'
      : daysUntil <= 90
      ? 'text-[hsl(45,60%,50%)]'
      : 'text-[hsl(152,62%,38%)]'

  return (
    <Link
      href={item.href}
      className="flex items-center gap-3 px-4 py-3 hover:bg-muted/40 transition-colors group"
    >
      <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-muted">
        <Icon className="h-4 w-4 text-muted-foreground" />
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium truncate">{item.name}</p>
        {item.category && (
          <p className="text-xs text-muted-foreground capitalize">{item.category}</p>
        )}
      </div>
      <div className="text-right shrink-0">
        <p className={cn('text-xs font-semibold', dateColor)}>{dateLabel}</p>
        <p className="text-[10px] text-muted-foreground">
          {new Date(item.expires_at).toLocaleDateString('en', {
            month: 'short',
            day: 'numeric',
            year: 'numeric',
          })}
        </p>
      </div>
      <ChevronRight className="h-4 w-4 text-muted-foreground transition-transform group-hover:translate-x-0.5 shrink-0" />
    </Link>
  )
}

function StatChip({ count, label, activeColor, activeClass }: {
  count: number
  label: string
  activeColor: string
  activeClass?: string
}) {
  if (count === 0) {
    return (
      <span className="inline-flex items-center gap-1 rounded-full border border-border/40 px-3 py-1 text-xs text-muted-foreground">
        <span className="font-semibold">0</span> {label}
      </span>
    )
  }
  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full border px-3 py-1 text-xs font-medium ${activeClass ?? ''}`}
      style={activeClass ? undefined : { borderColor: activeColor + '50', color: activeColor, background: activeColor + '15' }}
    >
      <span className="font-bold">{count}</span> {label}
    </span>
  )
}

export function ExpiryRadarPage({
  property,
  documents,
  inventoryItems,
  leases,
}: ExpiryRadarPageProps) {
  const allItems: DocItem[] = [
    ...documents
      .filter((d) => d.expires_at !== null)
      .map((d) => ({
        id: d.id,
        name: d.name,
        category: d.category,
        expires_at: d.expires_at!,
        type: 'document' as const,
        href: '/documents',
      })),
    ...inventoryItems
      .filter((i) => i.warranty_expires !== null)
      .map((i) => ({
        id: i.id,
        name: i.name,
        category: i.category,
        expires_at: i.warranty_expires!,
        type: 'warranty' as const,
        href: `/inventory/${i.id}`,
      })),
    ...leases
      .filter((l) => l.end_date !== null)
      .map((l) => ({
        id: l.id,
        name: `Lease: ${l.tenant_name ?? 'Unknown'}`,
        category: l.status,
        expires_at: l.end_date!,
        type: 'lease' as const,
        href: '/tenant/leases',
      })),
  ]

  const withDays = allItems.map((item) => ({
    ...item,
    daysUntil: Math.round(
      (new Date(item.expires_at).getTime() - Date.now()) / 86400000
    ),
  }))

  const expired = withDays
    .filter((i) => i.daysUntil < 0)
    .sort((a, b) => b.daysUntil - a.daysUntil) // most recently expired first (least negative)

  const expiringSoon = withDays
    .filter((i) => i.daysUntil >= 0 && i.daysUntil <= 30)
    .sort((a, b) => a.daysUntil - b.daysUntil)

  const upcoming = withDays
    .filter((i) => i.daysUntil >= 31 && i.daysUntil <= 90)
    .sort((a, b) => a.daysUntil - b.daysUntil)

  const ok = withDays
    .filter((i) => i.daysUntil > 90)
    .sort((a, b) => a.daysUntil - b.daysUntil)

  return (
    <>
      <PageHeader title="Expiry Radar" description={property.name} backHref="/documents" />
      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6">
        {/* Summary stats */}
        <div className="flex flex-wrap gap-2">
          <StatChip
            count={expired.length}
            label="expired"
            activeColor="hsl(0,68%,44%)"
            activeClass="bg-destructive/10 text-destructive"
          />
          <StatChip
            count={expiringSoon.length}
            label="expiring soon"
            activeColor="hsl(22,68%,41%)"
          />
          <StatChip
            count={upcoming.length}
            label="upcoming"
            activeColor="hsl(45,75%,42%)"
          />
          <StatChip
            count={ok.length}
            label="OK"
            activeColor="hsl(152,62%,38%)"
          />
        </div>

        {allItems.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
            <ScanSearch className="h-10 w-10 opacity-30" />
            <p className="text-sm">No items with expiry dates</p>
            <p className="text-xs opacity-60">
              Add expiry dates to documents, warranties, and leases
            </p>
          </div>
        ) : (
          <>
            <Section
              title="Expired"
              items={expired}
              color="hsl(0,68%,44%)"
              bgColor="hsl(0,68%,44%,0.1)"
              emptyText="No expired items"
            />
            <Section
              title="Expiring Soon ≤ 30 days"
              items={expiringSoon}
              color="hsl(22,68%,41%)"
              bgColor="hsl(22,68%,41%,0.1)"
              emptyText="Nothing expiring in the next 30 days"
            />
            <Section
              title="Upcoming ≤ 90 days"
              items={upcoming}
              color="hsl(45,75%,42%)"
              bgColor="hsl(45,75%,42%,0.1)"
              emptyText="Nothing expiring in the next 90 days"
            />
            <Section
              title="OK > 90 days"
              items={ok}
              color="hsl(152,62%,38%)"
              bgColor="hsl(152,62%,38%,0.1)"
              emptyText="No items valid beyond 90 days"
            />
          </>
        )}
      </div>
    </>
  )
}
