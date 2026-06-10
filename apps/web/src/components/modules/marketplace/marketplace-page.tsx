'use client'

import * as React from 'react'
import { Star, Phone, Globe, Search, Wrench, Zap, Droplets, Wind, Paintbrush, ShieldCheck, Scissors, Hammer } from 'lucide-react'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'

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

const CATEGORY_ICONS: Record<ServiceCategory, React.ComponentType<{ className?: string }>> = {
  plumbing:    Droplets,
  electrical:  Zap,
  hvac:        Wind,
  cleaning:    Scissors,
  painting:    Paintbrush,
  security:    ShieldCheck,
  landscaping: Scissors,
  general:     Hammer,
}

const CATEGORY_COLORS: Record<ServiceCategory, string> = {
  plumbing:    'hsl(220,62%,52%)',
  electrical:  'hsl(45,75%,42%)',
  hvac:        'hsl(180,52%,42%)',
  cleaning:    'hsl(152,62%,42%)',
  painting:    'hsl(310,52%,48%)',
  security:    'hsl(0,68%,44%)',
  landscaping: 'hsl(100,52%,38%)',
  general:     'hsl(22,68%,45%)',
}

const PROVIDERS: ServiceProvider[] = [
  {
    id: '1',
    name: 'AquaFix Plumbing',
    category: 'plumbing',
    description: 'Emergency and scheduled plumbing repairs, pipe installation, drain cleaning.',
    rating: 4.8,
    reviewCount: 124,
    priceRange: '€€',
    responseTime: '2h',
    phone: '+351 91 234 5678',
    verified: true,
    tags: ['Emergency', 'Drain cleaning', 'Pipe repair'],
  },
  {
    id: '2',
    name: 'VoltPro Electricians',
    category: 'electrical',
    description: 'Certified electricians for panel upgrades, rewiring, smart home installation.',
    rating: 4.9,
    reviewCount: 89,
    priceRange: '€€',
    responseTime: '4h',
    phone: '+351 96 345 6789',
    website: 'https://voltpro.example.com',
    verified: true,
    tags: ['Smart home', 'Panel upgrade', 'LED lighting'],
  },
  {
    id: '3',
    name: 'ClimaTech HVAC',
    category: 'hvac',
    description: 'Air conditioning installation, maintenance, and repair. Heat pump specialists.',
    rating: 4.7,
    reviewCount: 56,
    priceRange: '€€€',
    responseTime: '24h',
    phone: '+351 93 456 7890',
    verified: true,
    tags: ['AC install', 'Heat pump', 'Filter service'],
  },
  {
    id: '4',
    name: 'SparkClean Services',
    category: 'cleaning',
    description: 'Deep cleaning, move-in/out cleaning, regular housekeeping.',
    rating: 4.6,
    reviewCount: 203,
    priceRange: '€',
    responseTime: '24h',
    phone: '+351 91 567 8901',
    verified: true,
    tags: ['Deep clean', 'Move-out', 'Weekly service'],
  },
  {
    id: '5',
    name: 'ColorMaster Painters',
    category: 'painting',
    description: 'Interior and exterior painting, wallpaper, decorative finishes.',
    rating: 4.5,
    reviewCount: 78,
    priceRange: '€€',
    responseTime: '48h',
    verified: false,
    tags: ['Interior', 'Exterior', 'Wallpaper'],
  },
  {
    id: '6',
    name: 'SecureHome Systems',
    category: 'security',
    description: 'CCTV installation, alarm systems, smart locks and access control.',
    rating: 4.8,
    reviewCount: 45,
    priceRange: '€€€',
    responseTime: '48h',
    phone: '+351 96 678 9012',
    website: 'https://securehome.example.com',
    verified: true,
    tags: ['CCTV', 'Smart locks', 'Alarm systems'],
  },
  {
    id: '7',
    name: 'GreenThumb Landscaping',
    category: 'landscaping',
    description: 'Garden maintenance, lawn care, irrigation systems, tree trimming.',
    rating: 4.4,
    reviewCount: 67,
    priceRange: '€€',
    responseTime: '48h',
    verified: false,
    tags: ['Lawn care', 'Tree trimming', 'Irrigation'],
  },
  {
    id: '8',
    name: 'HandyPro General',
    category: 'general',
    description: 'All-round handyman service: furniture assembly, minor repairs, tile work.',
    rating: 4.6,
    reviewCount: 312,
    priceRange: '€',
    responseTime: '4h',
    phone: '+351 93 789 0123',
    verified: true,
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

export function MarketplacePage() {
  const [search, setSearch] = React.useState('')
  const [activeCategory, setActiveCategory] = React.useState<ServiceCategory | 'all'>('all')

  const filtered = PROVIDERS.filter((p) => {
    const matchesCategory = activeCategory === 'all' || p.category === activeCategory
    const matchesSearch =
      !search ||
      p.name.toLowerCase().includes(search.toLowerCase()) ||
      p.description.toLowerCase().includes(search.toLowerCase()) ||
      p.tags.some((t) => t.toLowerCase().includes(search.toLowerCase()))
    return matchesCategory && matchesSearch
  })

  return (
    <>
      <PageHeader title="Marketplace" description="Trusted service providers" />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Search */}
        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <input
            type="search"
            placeholder="Search services..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="h-11 w-full rounded-xl border border-border glass-light pl-10 pr-4 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
          />
        </div>

        {/* Category tabs */}
        <div className="flex gap-2 overflow-x-auto scrollbar-hide">
          {CATEGORY_TABS.map(({ id, label }) => (
            <button
              key={id}
              type="button"
              onClick={() => setActiveCategory(id)}
              className={`shrink-0 rounded-full px-3 py-1 text-xs font-medium transition-colors ${
                activeCategory === id
                  ? 'bg-primary text-white'
                  : 'glass-light text-muted-foreground hover:text-foreground'
              }`}
            >
              {label}
            </button>
          ))}
        </div>

        {/* Provider list */}
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-center">
            <div className="flex h-14 w-14 items-center justify-center rounded-2xl glass-standard">
              <Wrench className="h-7 w-7 text-muted-foreground" />
            </div>
            <p className="font-semibold text-foreground">No providers found</p>
            <p className="text-sm text-muted-foreground max-w-[200px]">Try a different search or category</p>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {filtered.map((provider) => (
              <ProviderCard key={provider.id} provider={provider} />
            ))}
          </div>
        )}

        <p className="text-center text-xs text-muted-foreground py-4">
          Directory is illustrative. Verify credentials before hiring.
        </p>
      </div>
    </>
  )
}

function ProviderCard({ provider }: { provider: ServiceProvider }) {
  const Icon = CATEGORY_ICONS[provider.category]
  const color = CATEGORY_COLORS[provider.category]

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
                {provider.verified && (
                  <ShieldCheck className="h-3.5 w-3.5 shrink-0 text-[hsl(152,62%,48%)]" />
                )}
              </div>
              <p className="text-xs text-muted-foreground mt-0.5 line-clamp-2">{provider.description}</p>
            </div>
          </div>

          {/* Rating + price */}
          <div className="mt-2 flex items-center gap-3">
            <div className="flex items-center gap-1">
              <Star className="h-3 w-3 fill-[hsl(45,75%,52%)] text-[hsl(45,75%,52%)]" />
              <span className="text-xs font-medium text-foreground">{provider.rating}</span>
              <span className="text-[10px] text-muted-foreground">({provider.reviewCount})</span>
            </div>
            <span className="text-xs text-muted-foreground">{provider.priceRange}</span>
            <span className="text-xs text-muted-foreground">Responds in {provider.responseTime}</span>
          </div>

          {/* Tags */}
          <div className="mt-2 flex flex-wrap gap-1">
            {provider.tags.map((tag) => (
              <span key={tag} className="rounded-full glass-light px-2 py-0.5 text-[10px] text-muted-foreground">
                {tag}
              </span>
            ))}
          </div>

          {/* Contact buttons */}
          {(provider.phone || provider.website) && (
            <div className="mt-3 flex gap-2">
              {provider.phone && (
                <a
                  href={`tel:${provider.phone}`}
                  className="flex items-center gap-1.5 rounded-lg glass-light px-3 py-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
                >
                  <Phone className="h-3 w-3" />
                  Call
                </a>
              )}
              {provider.website && (
                <a
                  href={provider.website}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-1.5 rounded-lg glass-light px-3 py-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
                >
                  <Globe className="h-3 w-3" />
                  Website
                </a>
              )}
            </div>
          )}
        </div>
      </div>
    </Card>
  )
}
