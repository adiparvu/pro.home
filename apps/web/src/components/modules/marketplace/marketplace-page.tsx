'use client'

import * as React from 'react'
import Link from 'next/link'
import {
  Star, Phone, Globe, Mail, Search, Wrench, Zap, Droplets, Wind,
  Paintbrush, ShieldCheck, Scissors, Hammer, Plus, Heart, Trash2,
  ChevronDown, ChevronUp, BookUser,
} from 'lucide-react'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { createClient } from '@/lib/supabase/client'
import { cn } from '@/lib/utils'
import type { MarketplaceContact } from '@/lib/supabase/types'

// ─── Static directory data ────────────────────────────────────────────────────

type ServiceCategory = 'plumbing' | 'electrical' | 'hvac' | 'cleaning' | 'painting' | 'security' | 'landscaping' | 'general'

interface ServiceProvider {
  id: string
  name: string
  category: ServiceCategory
  description: string
  rating: number
  reviewCount: number
  priceRange: '€' | '€€' | '€€€'
  responseTime: string
  phone?: string
  website?: string
  verified: boolean
  tags: string[]
}

const CATEGORY_ICONS: Record<string, React.ComponentType<{ className?: string }>> = {
  plumbing:    Droplets,
  electrical:  Zap,
  hvac:        Wind,
  cleaning:    Scissors,
  painting:    Paintbrush,
  security:    ShieldCheck,
  landscaping: Scissors,
  general:     Hammer,
}

const CATEGORY_COLORS: Record<string, string> = {
  plumbing:    'hsl(220,62%,52%)',
  electrical:  'hsl(45,75%,42%)',
  hvac:        'hsl(180,52%,42%)',
  cleaning:    'hsl(152,62%,42%)',
  painting:    'hsl(310,52%,48%)',
  security:    'hsl(0,68%,44%)',
  landscaping: 'hsl(100,52%,38%)',
  general:     'hsl(22,68%,45%)',
}

function categoryColor(cat: string): string {
  const key = cat.toLowerCase().split(' ')[0] as ServiceCategory
  return CATEGORY_COLORS[key] ?? 'hsl(var(--muted-foreground))'
}

function categoryIcon(cat: string): React.ComponentType<{ className?: string }> {
  const key = cat.toLowerCase().split(' ')[0] as ServiceCategory
  return CATEGORY_ICONS[key] ?? Hammer
}

const PROVIDERS: ServiceProvider[] = [
  {
    id: '1', name: 'AquaFix Plumbing', category: 'plumbing',
    description: 'Emergency and scheduled plumbing repairs, pipe installation, drain cleaning.',
    rating: 4.8, reviewCount: 124, priceRange: '€€', responseTime: '2h',
    phone: '+351 91 234 5678', verified: true,
    tags: ['Emergency', 'Drain cleaning', 'Pipe repair'],
  },
  {
    id: '2', name: 'VoltPro Electricians', category: 'electrical',
    description: 'Certified electricians for panel upgrades, rewiring, smart home installation.',
    rating: 4.9, reviewCount: 89, priceRange: '€€', responseTime: '4h',
    phone: '+351 96 345 6789', website: 'https://voltpro.example.com', verified: true,
    tags: ['Smart home', 'Panel upgrade', 'LED lighting'],
  },
  {
    id: '3', name: 'ClimaTech HVAC', category: 'hvac',
    description: 'Air conditioning installation, maintenance, and repair. Heat pump specialists.',
    rating: 4.7, reviewCount: 56, priceRange: '€€€', responseTime: '24h',
    phone: '+351 93 456 7890', verified: true,
    tags: ['AC install', 'Heat pump', 'Filter service'],
  },
  {
    id: '4', name: 'SparkClean Services', category: 'cleaning',
    description: 'Deep cleaning, move-in/out cleaning, regular housekeeping.',
    rating: 4.6, reviewCount: 203, priceRange: '€', responseTime: '24h',
    phone: '+351 91 567 8901', verified: true,
    tags: ['Deep clean', 'Move-out', 'Weekly service'],
  },
  {
    id: '5', name: 'ColorMaster Painters', category: 'painting',
    description: 'Interior and exterior painting, wallpaper, decorative finishes.',
    rating: 4.5, reviewCount: 78, priceRange: '€€', responseTime: '48h',
    verified: false, tags: ['Interior', 'Exterior', 'Wallpaper'],
  },
  {
    id: '6', name: 'SecureHome Systems', category: 'security',
    description: 'CCTV installation, alarm systems, smart locks and access control.',
    rating: 4.8, reviewCount: 45, priceRange: '€€€', responseTime: '48h',
    phone: '+351 96 678 9012', website: 'https://securehome.example.com', verified: true,
    tags: ['CCTV', 'Smart locks', 'Alarm systems'],
  },
  {
    id: '7', name: 'GreenThumb Landscaping', category: 'landscaping',
    description: 'Garden maintenance, lawn care, irrigation systems, tree trimming.',
    rating: 4.4, reviewCount: 67, priceRange: '€€', responseTime: '48h',
    verified: false, tags: ['Lawn care', 'Tree trimming', 'Irrigation'],
  },
  {
    id: '8', name: 'HandyPro General', category: 'general',
    description: 'All-round handyman service: furniture assembly, minor repairs, tile work.',
    rating: 4.6, reviewCount: 312, priceRange: '€', responseTime: '4h',
    phone: '+351 93 789 0123', verified: true,
    tags: ['Assembly', 'Tile', 'Minor repairs'],
  },
]

const CATEGORY_TABS: { id: ServiceCategory | 'all'; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'plumbing', label: 'Plumbing' },
  { id: 'electrical', label: 'Electrical' },
  { id: 'hvac', label: 'HVAC' },
  { id: 'cleaning', label: 'Cleaning' },
  { id: 'painting', label: 'Painting' },
  { id: 'security', label: 'Security' },
  { id: 'landscaping', label: 'Landscaping' },
  { id: 'general', label: 'Handyman' },
]

// ─── Props ────────────────────────────────────────────────────────────────────

interface MarketplacePageProps {
  propertyId: string | null
  initialContacts: MarketplaceContact[]
}

// ─── Main component ───────────────────────────────────────────────────────────

export function MarketplacePage({ propertyId, initialContacts }: MarketplacePageProps) {
  const [activeTab, setActiveTab] = React.useState<'directory' | 'contacts'>('directory')
  const [search, setSearch] = React.useState('')
  const [activeCategory, setActiveCategory] = React.useState<ServiceCategory | 'all'>('all')
  const [contacts, setContacts] = React.useState<MarketplaceContact[]>(initialContacts)

  const filteredProviders = PROVIDERS.filter((p) => {
    const matchesCategory = activeCategory === 'all' || p.category === activeCategory
    const matchesSearch =
      !search ||
      p.name.toLowerCase().includes(search.toLowerCase()) ||
      p.description.toLowerCase().includes(search.toLowerCase()) ||
      p.tags.some((t) => t.toLowerCase().includes(search.toLowerCase()))
    return matchesCategory && matchesSearch
  })

  const filteredContacts = contacts.filter((c) =>
    !search ||
    c.name.toLowerCase().includes(search.toLowerCase()) ||
    (c.description ?? '').toLowerCase().includes(search.toLowerCase()) ||
    c.category.toLowerCase().includes(search.toLowerCase()) ||
    c.tags.some((t) => t.toLowerCase().includes(search.toLowerCase()))
  )

  async function toggleFavorite(id: string, current: boolean) {
    setContacts((prev) => prev.map((c) => c.id === id ? { ...c, is_favorite: !current } : c))
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('marketplace_contacts').update({ is_favorite: !current }).eq('id', id)
  }

  async function deleteContact(id: string) {
    setContacts((prev) => prev.filter((c) => c.id !== id))
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('marketplace_contacts').delete().eq('id', id)
  }

  return (
    <>
      <PageHeader
        title="Marketplace"
        description="Services & trusted contacts"
        action={propertyId ? { label: 'Add Contact', href: '/marketplace/contacts/new' } : undefined}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Tab switcher */}
        <div className="flex gap-1 rounded-xl glass-light p-1">
          <button
            type="button"
            onClick={() => setActiveTab('directory')}
            className={cn(
              'flex-1 rounded-lg py-2 text-xs font-medium transition-colors',
              activeTab === 'directory' ? 'bg-primary text-white' : 'text-muted-foreground hover:text-foreground'
            )}
          >
            Directory
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('contacts')}
            className={cn(
              'flex-1 rounded-lg py-2 text-xs font-medium transition-colors flex items-center justify-center gap-1.5',
              activeTab === 'contacts' ? 'bg-primary text-white' : 'text-muted-foreground hover:text-foreground'
            )}
          >
            My Contacts
            {contacts.length > 0 && (
              <span className={cn('rounded-full px-1.5 py-0.5 text-[10px] font-semibold', activeTab === 'contacts' ? 'bg-white/20' : 'bg-primary/20 text-primary')}>
                {contacts.length}
              </span>
            )}
          </button>
        </div>

        {/* Search */}
        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <input
            type="search"
            placeholder={activeTab === 'directory' ? 'Search services…' : 'Search my contacts…'}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="h-11 w-full rounded-xl border border-border glass-light pl-10 pr-4 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
          />
        </div>

        {activeTab === 'directory' ? (
          <>
            {/* Category tabs */}
            <div className="flex gap-2 overflow-x-auto scrollbar-hide">
              {CATEGORY_TABS.map(({ id, label }) => (
                <button
                  key={id}
                  type="button"
                  onClick={() => setActiveCategory(id)}
                  className={cn(
                    'shrink-0 rounded-full px-3 py-1 text-xs font-medium transition-colors',
                    activeCategory === id ? 'bg-primary text-white' : 'glass-light text-muted-foreground hover:text-foreground'
                  )}
                >
                  {label}
                </button>
              ))}
            </div>

            {filteredProviders.length === 0 ? (
              <EmptyState icon={<Wrench className="h-7 w-7 text-muted-foreground" />} title="No providers found" subtitle="Try a different search or category" />
            ) : (
              <div className="flex flex-col gap-3">
                {filteredProviders.map((p) => <ProviderCard key={p.id} provider={p} />)}
              </div>
            )}
            <p className="text-center text-xs text-muted-foreground py-4">
              Directory is illustrative. Verify credentials before hiring.
            </p>
          </>
        ) : (
          <>
            {filteredContacts.length === 0 && contacts.length === 0 ? (
              <EmptyState
                icon={<BookUser className="h-7 w-7 text-muted-foreground" />}
                title="No saved contacts yet"
                subtitle="Save your trusted plumbers, cleaners and contractors here."
                action={propertyId ? <Link href="/marketplace/contacts/new" className="flex items-center gap-1 rounded-lg bg-primary px-3 py-2 text-xs text-white font-medium"><Plus className="h-3.5 w-3.5" />Add first contact</Link> : undefined}
              />
            ) : filteredContacts.length === 0 ? (
              <EmptyState icon={<Search className="h-7 w-7 text-muted-foreground" />} title="No results" subtitle="Try different search terms" />
            ) : (
              <div className="flex flex-col gap-3">
                {filteredContacts.map((c) => (
                  <ContactCard
                    key={c.id}
                    contact={c}
                    onToggleFavorite={toggleFavorite}
                    onDelete={deleteContact}
                  />
                ))}
              </div>
            )}
          </>
        )}
      </div>
    </>
  )
}

// ─── Provider card (directory) ────────────────────────────────────────────────

function ProviderCard({ provider }: { provider: ServiceProvider }) {
  const Icon = CATEGORY_ICONS[provider.category] ?? Hammer
  const color = CATEGORY_COLORS[provider.category] ?? 'hsl(var(--muted-foreground))'

  return (
    <Card variant="default" padding="md">
      <div className="flex items-start gap-3">
        <div
          className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl [&>svg]:text-[var(--icon-color)]"
          style={{ background: `${color}18`, border: `1px solid ${color}30`, '--icon-color': color } as React.CSSProperties}
        >
          <Icon className="h-6 w-6" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <div className="flex items-center gap-1.5">
                <p className="text-sm font-semibold text-foreground truncate">{provider.name}</p>
                {provider.verified && <ShieldCheck className="h-3.5 w-3.5 shrink-0 text-[hsl(152,62%,48%)]" />}
              </div>
              <p className="text-xs text-muted-foreground mt-0.5 line-clamp-2">{provider.description}</p>
            </div>
          </div>

          <div className="mt-2 flex items-center gap-3">
            <div className="flex items-center gap-1">
              <Star className="h-3 w-3 fill-[hsl(45,75%,52%)] text-[hsl(45,75%,52%)]" />
              <span className="text-xs font-medium text-foreground">{provider.rating}</span>
              <span className="text-[10px] text-muted-foreground">({provider.reviewCount})</span>
            </div>
            <span className="text-xs text-muted-foreground">{provider.priceRange}</span>
            <span className="text-xs text-muted-foreground">Responds in {provider.responseTime}</span>
          </div>

          <div className="mt-2 flex flex-wrap gap-1">
            {provider.tags.map((tag) => (
              <span key={tag} className="rounded-full glass-light px-2 py-0.5 text-[10px] text-muted-foreground">{tag}</span>
            ))}
          </div>

          {(provider.phone || provider.website) && (
            <div className="mt-3 flex gap-2">
              {provider.phone && (
                <a href={`tel:${provider.phone}`} className="flex items-center gap-1.5 rounded-lg glass-light px-3 py-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors">
                  <Phone className="h-3 w-3" />Call
                </a>
              )}
              {provider.website && (
                <a href={provider.website} target="_blank" rel="noopener noreferrer" className="flex items-center gap-1.5 rounded-lg glass-light px-3 py-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors">
                  <Globe className="h-3 w-3" />Website
                </a>
              )}
            </div>
          )}
        </div>
      </div>
    </Card>
  )
}

// ─── Contact card (My Contacts) ───────────────────────────────────────────────

function ContactCard({
  contact,
  onToggleFavorite,
  onDelete,
}: {
  contact: MarketplaceContact
  onToggleFavorite: (id: string, current: boolean) => void
  onDelete: (id: string) => void
}) {
  const [expanded, setExpanded] = React.useState(false)
  const color = categoryColor(contact.category)
  const Icon = categoryIcon(contact.category)

  return (
    <Card variant="default" padding="md">
      <div className="flex items-start gap-3">
        <div
          className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl [&>svg]:text-[var(--icon-color)]"
          style={{ background: `${color}18`, border: `1px solid ${color}30`, '--icon-color': color } as React.CSSProperties}
        >
          <Icon className="h-6 w-6" />
        </div>

        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <div className="flex items-center gap-1.5 flex-wrap">
                <p className="text-sm font-semibold text-foreground truncate">{contact.name}</p>
                <Badge variant="neutral" size="xs">{contact.category}</Badge>
                {contact.is_favorite && <Heart className="h-3 w-3 fill-destructive text-destructive shrink-0" />}
              </div>
              {contact.description && (
                <p className="text-xs text-muted-foreground mt-0.5 line-clamp-2">{contact.description}</p>
              )}
            </div>
            <div className="flex items-center gap-1 shrink-0">
              <button
                type="button"
                onClick={() => onToggleFavorite(contact.id, contact.is_favorite)}
                className="flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground hover:text-foreground transition-colors"
              >
                <Heart className={cn('h-3.5 w-3.5', contact.is_favorite && 'fill-destructive text-destructive')} />
              </button>
              <button
                type="button"
                onClick={() => setExpanded((v) => !v)}
                className="flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground hover:text-foreground transition-colors"
              >
                {expanded ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
              </button>
            </div>
          </div>

          {/* Rating */}
          {contact.rating != null && (
            <div className="mt-1 flex items-center gap-1">
              {[1,2,3,4,5].map((n) => (
                <Star key={n} className={cn('h-3 w-3', n <= contact.rating! ? 'fill-[hsl(45,75%,52%)] text-[hsl(45,75%,52%)]' : 'text-muted-foreground')} />
              ))}
            </div>
          )}

          {/* Tags */}
          {contact.tags.length > 0 && (
            <div className="mt-2 flex flex-wrap gap-1">
              {contact.tags.map((tag) => (
                <span key={tag} className="rounded-full glass-light px-2 py-0.5 text-[10px] text-muted-foreground">{tag}</span>
              ))}
            </div>
          )}

          {/* Contact buttons (always visible) */}
          {(contact.phone || contact.email || contact.website) && (
            <div className="mt-3 flex flex-wrap gap-2">
              {contact.phone && (
                <a href={`tel:${contact.phone}`} className="flex items-center gap-1.5 rounded-lg glass-light px-3 py-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors">
                  <Phone className="h-3 w-3" />Call
                </a>
              )}
              {contact.email && (
                <a href={`mailto:${contact.email}`} className="flex items-center gap-1.5 rounded-lg glass-light px-3 py-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors">
                  <Mail className="h-3 w-3" />Email
                </a>
              )}
              {contact.website && (
                <a href={contact.website} target="_blank" rel="noopener noreferrer" className="flex items-center gap-1.5 rounded-lg glass-light px-3 py-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors">
                  <Globe className="h-3 w-3" />Website
                </a>
              )}
            </div>
          )}

          {/* Expanded section */}
          {expanded && (
            <div className="mt-3 flex flex-col gap-2 border-t border-border/40 pt-3">
              {contact.notes && (
                <p className="text-xs text-muted-foreground">{contact.notes}</p>
              )}
              <button
                type="button"
                onClick={() => onDelete(contact.id)}
                className="flex items-center gap-1 self-start text-xs text-destructive hover:text-destructive/80 transition-colors"
              >
                <Trash2 className="h-3 w-3" />Remove contact
              </button>
            </div>
          )}
        </div>
      </div>
    </Card>
  )
}

// ─── Empty state ──────────────────────────────────────────────────────────────

function EmptyState({ icon, title, subtitle, action }: {
  icon: React.ReactNode
  title: string
  subtitle: string
  action?: React.ReactNode
}) {
  return (
    <div className="flex flex-col items-center gap-3 py-16 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-2xl glass-standard">
        {icon}
      </div>
      <p className="font-semibold text-foreground">{title}</p>
      <p className="text-sm text-muted-foreground max-w-[220px]">{subtitle}</p>
      {action}
    </div>
  )
}
