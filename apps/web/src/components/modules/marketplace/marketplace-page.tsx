'use client'

import * as React from 'react'
import Link from 'next/link'
import {
  Star, Phone, Globe, Mail, Search, Wrench, Zap, Droplets, Wind,
  Paintbrush, ShieldCheck, Scissors, Hammer, Plus, Heart, Trash2,
  ChevronDown, ChevronUp, BookUser, ClipboardList, AlertCircle,
  CheckCircle2, XCircle, CalendarDays, ChevronRight, Siren,
} from 'lucide-react'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { StatusChip } from '@/components/ui/chip'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { SegmentedControl } from '@/components/ui/segmented-control'
import { toast } from '@/hooks/use-toast'
import { createClient } from '@/lib/supabase/client'
import { cn } from '@/lib/utils'
import type { MarketplaceContact, ServiceRequest, ServiceRequestStatus } from '@/lib/supabase/types'

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

const STATUS_NEXT: Partial<Record<ServiceRequestStatus, ServiceRequestStatus>> = {
  pending:     'quoted',
  quoted:      'scheduled',
  scheduled:   'in_progress',
  in_progress: 'completed',
}

// ─── Props ────────────────────────────────────────────────────────────────────

interface MarketplacePageProps {
  propertyId: string | null
  initialContacts: MarketplaceContact[]
  initialRequests: ServiceRequest[]
  userId: string
}

// ─── Main component ───────────────────────────────────────────────────────────

export function MarketplacePage({ propertyId, initialContacts, initialRequests, userId }: MarketplacePageProps) {
  const confirmDialog = useConfirm()
  const [activeTab, setActiveTab] = React.useState<'directory' | 'contacts' | 'requests' | 'emergency'>('directory')
  const [search, setSearch] = React.useState('')
  const [activeCategory, setActiveCategory] = React.useState<ServiceCategory | 'all'>('all')
  const [contacts, setContacts] = React.useState<MarketplaceContact[]>(initialContacts)
  const [requests, setRequests] = React.useState<ServiceRequest[]>(initialRequests)

  // Request form state
  const [showRequestForm, setShowRequestForm] = React.useState(false)
  const [reqContactId, setReqContactId] = React.useState('')
  const [reqTitle, setReqTitle] = React.useState('')
  const [reqDescription, setReqDescription] = React.useState('')
  const [reqScheduledDate, setReqScheduledDate] = React.useState('')
  const [reqNotes, setReqNotes] = React.useState('')
  const [reqSaving, setReqSaving] = React.useState(false)
  const [reqError, setReqError] = React.useState<string | null>(null)

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

  async function toggleEmergency(id: string, current: boolean) {
    setContacts((prev) => prev.map((c) => c.id === id ? { ...c, is_emergency: !current } : c))
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('marketplace_contacts').update({ is_emergency: !current }).eq('id', id)
  }

  async function deleteContact(id: string) {
    setContacts((prev) => prev.filter((c) => c.id !== id))
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('marketplace_contacts').delete().eq('id', id)
  }

  function openRequestForm(contactId?: string) {
    setReqContactId(contactId ?? '')
    setReqTitle(''); setReqDescription(''); setReqScheduledDate(''); setReqNotes('')
    setReqError(null); setShowRequestForm(true)
    setActiveTab('requests')
  }

  async function submitRequest(e: React.FormEvent) {
    e.preventDefault()
    if (!reqTitle.trim() || !propertyId) return
    setReqSaving(true); setReqError(null)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data, error } = await (supabase as any).from('service_requests').insert({
      property_id: propertyId,
      contact_id: reqContactId || null,
      title: reqTitle.trim(),
      description: reqDescription.trim() || null,
      status: 'pending',
      scheduled_date: reqScheduledDate || null,
      notes: reqNotes.trim() || null,
      cost_currency: 'EUR',
      created_by: userId,
    }).select().single()
    if (error) {
      setReqError((error as { message: string }).message ?? 'Failed to save request')
    } else {
      setRequests((prev) => [data as ServiceRequest, ...prev])
      setShowRequestForm(false)
    }
    setReqSaving(false)
  }

  async function advanceStatus(req: ServiceRequest) {
    const next = STATUS_NEXT[req.status]
    if (!next) return
    const update: Partial<ServiceRequest> = { status: next }
    if (next === 'completed') update.completed_date = new Date().toISOString().split('T')[0] ?? null
    setRequests((prev) => prev.map((r) => r.id === req.id ? { ...r, ...update } : r))
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('service_requests').update(update).eq('id', req.id)
  }

  async function cancelRequest(id: string) {
    const ok = await confirmDialog({
      title: 'Cancel this service request?',
      confirmLabel: 'Cancel request',
      destructive: true,
    })
    if (!ok) return
    setRequests((prev) => prev.map((r) => r.id === id ? { ...r, status: 'cancelled' as const } : r))
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('service_requests').update({ status: 'cancelled' }).eq('id', id)
    toast.success('Request cancelled')
  }

  async function updateQuotedPrice(id: string, price: number) {
    setRequests((prev) => prev.map((r) => r.id === id ? { ...r, quoted_price: price } : r))
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('service_requests').update({ quoted_price: price }).eq('id', id)
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
        <SegmentedControl
          aria-label="Marketplace sections"
          value={activeTab}
          onChange={setActiveTab}
          options={[
            { value: 'directory', label: 'Directory' },
            { value: 'contacts', label: 'Contacts', count: contacts.length },
            { value: 'emergency', label: 'Emergency', count: contacts.filter((c) => (c as unknown as { is_emergency?: boolean }).is_emergency).length },
            {
              value: 'requests',
              label: 'Requests',
              count: requests.filter((r) => r.status !== 'completed' && r.status !== 'cancelled').length,
            },
          ]}
        />

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
        ) : activeTab === 'emergency' ? (
          <>
            <div className="flex items-center gap-2 rounded-xl border border-destructive/30 bg-destructive/10 px-4 py-3 text-sm text-destructive">
              <Siren className="h-4 w-4 shrink-0" />
              <span>Emergency contacts for urgent situations — call directly with one tap</span>
            </div>
            {contacts.filter((c) => (c as unknown as { is_emergency?: boolean }).is_emergency).length === 0 ? (
              <EmptyState
                icon={<Siren className="h-7 w-7 text-muted-foreground" />}
                title="No emergency contacts"
                subtitle='Go to Contacts and star contacts as "Emergency" to show them here'
              />
            ) : (
              <div className="flex flex-col gap-3">
                {contacts.filter((c) => (c as unknown as { is_emergency?: boolean }).is_emergency).map((c) => (
                  <ContactCard
                    key={c.id}
                    contact={c}
                    onToggleFavorite={toggleFavorite}
                    onToggleEmergency={toggleEmergency}
                    onDelete={deleteContact}
                    onRequestService={propertyId ? openRequestForm : undefined}
                    emergencyMode
                  />
                ))}
              </div>
            )}
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
                    onToggleEmergency={toggleEmergency}
                    onDelete={deleteContact}
                    onRequestService={propertyId ? openRequestForm : undefined}
                  />
                ))}
              </div>
            )}
          </>
        )}

        {activeTab === 'requests' && (
          <div className="flex flex-col gap-3">
            {/* New request form */}
            {showRequestForm && (
              <Card variant="default" padding="md">
                <div className="flex items-center justify-between mb-3">
                  <p className="text-sm font-semibold text-foreground">New service request</p>
                  <button type="button" onClick={() => setShowRequestForm(false)} className="text-muted-foreground hover:text-foreground">
                    <XCircle className="h-4 w-4" />
                  </button>
                </div>
                <form onSubmit={submitRequest} className="flex flex-col gap-3">
                  {reqError && (
                    <div className="flex items-center gap-2 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-xs text-destructive">
                      <AlertCircle className="h-3.5 w-3.5 shrink-0" />
                      {reqError}
                    </div>
                  )}
                  <div className="flex flex-col gap-1.5">
                    <label className="text-xs text-muted-foreground">Contact</label>
                    <select
                      value={reqContactId}
                      onChange={(e) => setReqContactId(e.target.value)}
                      className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground bg-transparent focus:outline-none focus:ring-2 focus:ring-primary/60"
                    >
                      <option value="">No specific contact</option>
                      {contacts.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
                    </select>
                  </div>
                  <div className="flex flex-col gap-1.5">
                    <label className="text-xs text-muted-foreground">What do you need? *</label>
                    <input
                      value={reqTitle}
                      onChange={(e) => setReqTitle(e.target.value)}
                      placeholder='e.g. "Fix leaking kitchen tap"'
                      required
                      className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                    />
                  </div>
                  <div className="flex flex-col gap-1.5">
                    <label className="text-xs text-muted-foreground">Description</label>
                    <input
                      value={reqDescription}
                      onChange={(e) => setReqDescription(e.target.value)}
                      placeholder="More details (optional)"
                      className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                    />
                  </div>
                  <div className="flex flex-col gap-1.5">
                    <label className="text-xs text-muted-foreground">Preferred date</label>
                    <input
                      type="date"
                      value={reqScheduledDate}
                      onChange={(e) => setReqScheduledDate(e.target.value)}
                      className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                    />
                  </div>
                  <button
                    type="submit"
                    disabled={reqSaving || !reqTitle.trim()}
                    className="h-10 w-full rounded-xl bg-primary text-sm font-medium text-white disabled:opacity-60 transition-opacity"
                  >
                    {reqSaving ? 'Saving…' : 'Create request'}
                  </button>
                </form>
              </Card>
            )}

            {/* Request list */}
            {requests.length === 0 && !showRequestForm ? (
              <EmptyState
                icon={<ClipboardList className="h-7 w-7 text-muted-foreground" />}
                title="No service requests yet"
                subtitle="Track quotes, scheduling, and work progress here."
                action={propertyId ? (
                  <button
                    type="button"
                    onClick={() => openRequestForm()}
                    className="flex items-center gap-1 rounded-lg bg-primary px-3 py-2 text-xs text-white font-medium"
                  >
                    <Plus className="h-3.5 w-3.5" />
                    New request
                  </button>
                ) : undefined}
              />
            ) : (
              <>
                {requests.map((req) => (
                  <RequestCard
                    key={req.id}
                    request={req}
                    contactName={req.contact_id ? (contacts.find((c) => c.id === req.contact_id)?.name ?? null) : null}
                    onAdvance={() => advanceStatus(req)}
                    onCancel={() => cancelRequest(req.id)}
                    onSetPrice={(p) => updateQuotedPrice(req.id, p)}
                  />
                ))}
                {!showRequestForm && (
                  <button
                    type="button"
                    onClick={() => openRequestForm()}
                    className="flex items-center justify-center gap-2 rounded-xl glass-light py-3 text-sm text-muted-foreground hover:text-foreground transition-colors"
                  >
                    <Plus className="h-4 w-4" />
                    New request
                  </button>
                )}
              </>
            )}
          </div>
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
  onToggleEmergency,
  onDelete,
  onRequestService,
  emergencyMode,
}: {
  contact: MarketplaceContact
  onToggleFavorite: (id: string, current: boolean) => void
  onToggleEmergency?: (id: string, current: boolean) => void
  onDelete: (id: string) => void
  onRequestService?: (contactId: string) => void
  emergencyMode?: boolean
}) {
  const isEmergency = (contact as unknown as { is_emergency?: boolean }).is_emergency ?? false
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
                {isEmergency && <Siren className="h-3 w-3 text-destructive shrink-0" />}
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
                title="Favourite"
              >
                <Heart className={cn('h-3.5 w-3.5', contact.is_favorite && 'fill-destructive text-destructive')} />
              </button>
              {onToggleEmergency && (
                <button
                  type="button"
                  onClick={() => onToggleEmergency(contact.id, isEmergency)}
                  className="flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground hover:text-destructive transition-colors"
                  title={isEmergency ? 'Remove from emergency' : 'Mark as emergency'}
                >
                  <Siren className={cn('h-3.5 w-3.5', isEmergency && 'text-destructive')} />
                </button>
              )}
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
              <div className="flex items-center gap-2 flex-wrap">
                {onRequestService && (
                  <button
                    type="button"
                    onClick={() => onRequestService(contact.id)}
                    className="flex items-center gap-1.5 rounded-lg bg-primary/10 border border-primary/20 px-3 py-1.5 text-xs font-medium text-primary hover:bg-primary/20 transition-colors"
                  >
                    <ClipboardList className="h-3 w-3" />
                    Request service
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => onDelete(contact.id)}
                  className="flex items-center gap-1 text-xs text-destructive hover:text-destructive/80 transition-colors"
                >
                  <Trash2 className="h-3 w-3" />Remove
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </Card>
  )
}

// ─── Request card ─────────────────────────────────────────────────────────────

function RequestCard({
  request, contactName, onAdvance, onCancel, onSetPrice,
}: {
  request: ServiceRequest
  contactName: string | null
  onAdvance: () => void
  onCancel: () => void
  onSetPrice: (p: number) => void
}) {
  const [editingPrice, setEditingPrice] = React.useState(false)
  const [priceInput, setPriceInput] = React.useState(String(request.quoted_price ?? ''))
  const nextStatus = STATUS_NEXT[request.status]
  const isTerminal = request.status === 'completed' || request.status === 'cancelled'

  return (
    <Card variant="default" padding="md">
      <div className="flex items-start justify-between gap-3">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <p className="text-sm font-semibold text-foreground">{request.title}</p>
            <StatusChip status={request.status} size="xs" />
          </div>
          {contactName && (
            <p className="text-xs text-muted-foreground mt-0.5">{contactName}</p>
          )}
          {request.description && (
            <p className="text-xs text-muted-foreground mt-0.5 line-clamp-2">{request.description}</p>
          )}
          <div className="mt-1.5 flex flex-wrap items-center gap-2 text-[10px] text-muted-foreground">
            {request.scheduled_date && (
              <span className="flex items-center gap-0.5">
                <CalendarDays className="h-3 w-3" />
                {new Date(request.scheduled_date).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
              </span>
            )}
            {request.quoted_price != null && !editingPrice && (
              <button
                type="button"
                onClick={() => setEditingPrice(true)}
                className="flex items-center gap-0.5 text-[hsl(152,62%,48%)] hover:underline"
              >
                €{request.quoted_price.toLocaleString()}
              </button>
            )}
          </div>
          {/* Quoted price inline edit */}
          {editingPrice && (
            <form
              onSubmit={(e) => {
                e.preventDefault()
                const p = parseFloat(priceInput)
                if (!isNaN(p)) { onSetPrice(p); setEditingPrice(false) }
              }}
              className="mt-2 flex items-center gap-2"
            >
              <input
                autoFocus
                type="number"
                value={priceInput}
                onChange={(e) => setPriceInput(e.target.value)}
                placeholder="Quoted price €"
                min="0"
                step="0.01"
                className="h-8 w-32 rounded-lg border border-border glass-light px-2 text-sm focus:outline-none focus:ring-1 focus:ring-primary/60"
              />
              <button type="submit" className="text-xs text-primary font-medium">Save</button>
              <button type="button" onClick={() => setEditingPrice(false)} className="text-xs text-muted-foreground">Cancel</button>
            </form>
          )}
          {request.status === 'quoted' && !editingPrice && request.quoted_price == null && (
            <button type="button" onClick={() => setEditingPrice(true)} className="mt-1.5 text-[10px] text-primary hover:underline">
              + Add quoted price
            </button>
          )}
        </div>
      </div>

      {!isTerminal && (
        <div className="mt-3 flex gap-2">
          {nextStatus && (
            <button
              type="button"
              onClick={onAdvance}
              className="flex items-center gap-1 rounded-lg bg-[hsl(152,62%,42%)] px-3 py-1.5 text-xs text-white font-medium hover:opacity-90 transition-opacity"
            >
              <ChevronRight className="h-3.5 w-3.5" />
              Mark as {nextStatus.replace(/_/g, ' ')}
            </button>
          )}
          <button
            type="button"
            onClick={onCancel}
            className="flex items-center gap-1 rounded-lg glass-light px-3 py-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
          >
            <XCircle className="h-3.5 w-3.5" />
            Cancel
          </button>
        </div>
      )}
      {request.status === 'completed' && (
        <div className="mt-2 flex items-center gap-1.5 text-xs text-[hsl(152,62%,48%)]">
          <CheckCircle2 className="h-3.5 w-3.5" />
          Completed{request.completed_date ? ` ${new Date(request.completed_date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}` : ''}
        </div>
      )}
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
