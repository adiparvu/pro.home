'use client'

import * as React from 'react'
import Link from 'next/link'
import { Search, Archive, Wrench, FolderOpen, Banknote, Flower2, Store, ChevronRight, Loader2 } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'

interface SearchResult {
  id: string
  type: 'inventory' | 'maintenance' | 'document' | 'finance' | 'garden' | 'marketplace'
  title: string
  subtitle?: string
  href: string
}

const TYPE_META = {
  inventory:   { label: 'Inventory',   icon: Archive,    color: 'hsl(185,62%,38%)' },
  maintenance: { label: 'Maintenance', icon: Wrench,     color: 'hsl(22,68%,41%)'  },
  document:    { label: 'Documents',   icon: FolderOpen, color: 'hsl(220,52%,46%)' },
  finance:     { label: 'Finances',    icon: Banknote,   color: 'hsl(45,75%,42%)'  },
  garden:      { label: 'Garden',      icon: Flower2,    color: 'hsl(120,52%,36%)' },
  marketplace: { label: 'Marketplace', icon: Store,      color: 'hsl(260,52%,52%)' },
} as const

function useDebounce<T>(value: T, delay: number): T {
  const [debounced, setDebounced] = React.useState(value)
  React.useEffect(() => {
    const t = setTimeout(() => setDebounced(value), delay)
    return () => clearTimeout(t)
  }, [value, delay])
  return debounced
}

export function SearchPage({ propertyId }: { propertyId: string }) {
  const [query, setQuery] = React.useState('')
  const [results, setResults] = React.useState<SearchResult[]>([])
  const [loading, setLoading] = React.useState(false)
  const debouncedQuery = useDebounce(query, 300)

  React.useEffect(() => {
    const q = debouncedQuery.trim()
    if (q.length < 2) {
      setResults([])
      return
    }

    async function doSearch() {
      setLoading(true)
      const supabase = createClient()

      const [
        { data: invItems },
        { data: tasks },
        { data: docs },
        { data: finances },
        { data: plants },
        { data: contacts },
      ] = await Promise.all([
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        (supabase as any)
          .from('inventory_items')
          .select('id, name, category, brand, model')
          .eq('property_id', propertyId)
          .ilike('name', `%${q}%`)
          .limit(5),
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        (supabase as any)
          .from('maintenance_tasks')
          .select('id, title, category, status')
          .eq('property_id', propertyId)
          .ilike('title', `%${q}%`)
          .limit(5),
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        (supabase as any)
          .from('documents')
          .select('id, name, category, file_name')
          .eq('property_id', propertyId)
          .ilike('name', `%${q}%`)
          .limit(5),
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        (supabase as any)
          .from('financial_records')
          .select('id, title, category, amount, type')
          .eq('property_id', propertyId)
          .ilike('title', `%${q}%`)
          .limit(5),
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        (supabase as any)
          .from('garden_plants')
          .select('id, name, species, common_name, status')
          .eq('property_id', propertyId)
          .ilike('name', `%${q}%`)
          .limit(5),
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        (supabase as any)
          .from('marketplace_contacts')
          .select('id, name, category, description')
          .eq('property_id', propertyId)
          .ilike('name', `%${q}%`)
          .limit(5),
      ])

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const combined: SearchResult[] = [
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        ...(invItems ?? []).map((item: any) => ({
          id: item.id,
          type: 'inventory' as const,
          title: item.name,
          subtitle: [item.brand, item.model, item.category].filter(Boolean).join(' · '),
          href: `/inventory/${item.id}`,
        })),
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        ...(tasks ?? []).map((t: any) => ({
          id: t.id,
          type: 'maintenance' as const,
          title: t.title,
          subtitle: `${t.category} · ${t.status}`.replace(/_/g, ' '),
          href: `/maintenance/${t.id}`,
        })),
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        ...(docs ?? []).map((d: any) => ({
          id: d.id,
          type: 'document' as const,
          title: d.name,
          subtitle: `${d.category} · ${d.file_name}`,
          href: `/documents/${d.id}`,
        })),
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        ...(finances ?? []).map((f: any) => ({
          id: f.id,
          type: 'finance' as const,
          title: f.title,
          subtitle: `${f.type ?? ''} · ${f.category} · €${f.amount}`.replace(/^·\s*/, ''),
          href: '/finances',
        })),
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        ...(plants ?? []).map((p: any) => ({
          id: p.id,
          type: 'garden' as const,
          title: p.name,
          subtitle: [p.common_name, p.species, p.status].filter(Boolean).join(' · ').replace(/_/g, ' '),
          href: `/garden/plants/${p.id}`,
        })),
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        ...(contacts ?? []).map((c: any) => ({
          id: c.id,
          type: 'marketplace' as const,
          title: c.name,
          subtitle: [c.category, c.description].filter(Boolean).join(' · '),
          href: '/marketplace',
        })),
      ]

      setResults(combined)
      setLoading(false)
    }

    doSearch()
  }, [debouncedQuery, propertyId])

  const grouped = results.reduce<Partial<Record<SearchResult['type'], SearchResult[]>>>((acc, r) => {
    if (!acc[r.type]) acc[r.type] = []
    acc[r.type]!.push(r)
    return acc
  }, {})

  const hasResults = results.length > 0
  const showEmpty = debouncedQuery.trim().length >= 2 && !loading && !hasResults
  const showHint = query.trim().length < 2 && !loading

  return (
    <>
      <PageHeader title="Search" />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[88px] md:pb-6">
        {/* Search input */}
        <div className="relative">
          <Search className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          {loading && (
            <Loader2 className="absolute right-3.5 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-muted-foreground" />
          )}
          <input
            // eslint-disable-next-line jsx-a11y/no-autofocus
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search inventory, tasks, documents…"
            className="h-12 w-full rounded-2xl border border-border glass-standard pl-10 pr-10 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
          />
        </div>

        {showHint && (
          <p className="py-8 text-center text-sm text-muted-foreground">
            Type at least 2 characters to search
          </p>
        )}

        {showEmpty && (
          <div className="flex flex-col items-center gap-2 py-12 text-center">
            <Search className="h-10 w-10 text-muted-foreground" />
            <p className="text-sm font-medium text-foreground">No results for &ldquo;{query}&rdquo;</p>
            <p className="text-xs text-muted-foreground">Try a different keyword</p>
          </div>
        )}

        {(Object.entries(grouped) as [SearchResult['type'], SearchResult[]][]).map(([type, items]) => {
          const meta = TYPE_META[type]
          const Icon = meta.icon
          return (
            <div key={type} className="flex flex-col gap-2">
              <div className="flex items-center gap-2 px-1">
                <Icon className="h-3.5 w-3.5" style={{ color: meta.color }} />
                <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  {meta.label}
                </p>
              </div>
              <div className="flex flex-col gap-1">
                {items.map((result) => (
                  <Link
                    key={result.id}
                    href={result.href}
                    className="group flex items-center gap-3 rounded-xl glass-light px-4 py-3 transition-colors hover:glass-standard focus-ring"
                  >
                    <div
                      className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg"
                      style={{ background: `${meta.color}18` }}
                    >
                      <Icon className="h-4 w-4" style={{ color: meta.color }} />
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium text-foreground">{result.title}</p>
                      {result.subtitle && (
                        <p className="truncate text-xs capitalize text-muted-foreground">{result.subtitle}</p>
                      )}
                    </div>
                    <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
                  </Link>
                ))}
              </div>
            </div>
          )
        })}
      </div>
    </>
  )
}
