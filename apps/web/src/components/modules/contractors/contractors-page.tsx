'use client'

import * as React from 'react'
import {
  HardHat, Plus, Pencil, Trash2, X, Loader2,
  Phone, Mail, Globe, Star, MapPin,
} from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import type { Property } from '@/lib/supabase/types'

interface Contractor {
  id: string
  property_id: string
  name: string
  category: string | null
  phone: string | null
  email: string | null
  website: string | null
  address: string | null
  notes: string | null
  rating: number | null
  is_preferred: boolean
  created_by: string | null
  created_at: string
  updated_at: string
}

interface ContractorsPageProps {
  property: Property
  userId: string
  initialContractors: Contractor[]
}

const CONTRACTOR_CATEGORIES = [
  'plumber', 'electrician', 'painter', 'handyman', 'carpenter',
  'roofer', 'landscaper', 'cleaner', 'locksmith', 'hvac', 'other',
]

const CATEGORY_COLORS: Record<string, string> = {
  plumber: 'hsl(210,75%,42%)',
  electrician: 'hsl(45,75%,42%)',
  painter: 'hsl(280,62%,52%)',
  handyman: 'hsl(22,68%,41%)',
  carpenter: 'hsl(30,68%,41%)',
  roofer: 'hsl(0,68%,44%)',
  landscaper: 'hsl(120,52%,36%)',
  cleaner: 'hsl(185,62%,38%)',
  locksmith: 'hsl(220,52%,46%)',
  hvac: 'hsl(152,62%,38%)',
  other: 'hsl(0,0%,50%)',
}

function StarRating({ rating, onChange }: { rating: number; onChange?: (r: number) => void }) {
  return (
    <div className="flex items-center gap-0.5">
      {[1, 2, 3, 4, 5].map((i) => (
        <button
          key={i}
          type={onChange ? 'button' : 'button'}
          onClick={onChange ? () => onChange(i) : undefined}
          className={cn(
            'transition-colors',
            onChange ? 'cursor-pointer hover:scale-110' : 'cursor-default pointer-events-none',
          )}
        >
          <Star
            className="h-3.5 w-3.5"
            fill={i <= rating ? 'hsl(45,75%,42%)' : 'none'}
            stroke={i <= rating ? 'hsl(45,75%,42%)' : 'currentColor'}
          />
        </button>
      ))}
    </div>
  )
}

export function ContractorsPage({ property, userId, initialContractors }: ContractorsPageProps) {
  const confirmDialog = useConfirm()
  const [contractors, setContractors] = React.useState<Contractor[]>(initialContractors)
  const [categoryFilter, setCategoryFilter] = React.useState<string>('all')
  const [showForm, setShowForm] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [editId, setEditId] = React.useState<string | null>(null)

  // Form state
  const [name, setName] = React.useState('')
  const [formCategory, setFormCategory] = React.useState('handyman')
  const [phone, setPhone] = React.useState('')
  const [email, setEmail] = React.useState('')
  const [website, setWebsite] = React.useState('')
  const [address, setAddress] = React.useState('')
  const [notes, setNotes] = React.useState('')
  const [rating, setRating] = React.useState(0)
  const [isPreferred, setIsPreferred] = React.useState(false)

  const categories = Array.from(new Set(contractors.map((c) => c.category).filter(Boolean))) as string[]

  const filtered = contractors.filter((c) => {
    if (categoryFilter === 'all') return true
    if (categoryFilter === 'preferred') return c.is_preferred
    return c.category === categoryFilter
  })

  function openNew() {
    setEditId(null)
    setName(''); setFormCategory('handyman'); setPhone(''); setEmail('')
    setWebsite(''); setAddress(''); setNotes(''); setRating(0); setIsPreferred(false)
    setShowForm(true)
  }

  function openEdit(c: Contractor) {
    setEditId(c.id)
    setName(c.name); setFormCategory(c.category ?? 'handyman'); setPhone(c.phone ?? '')
    setEmail(c.email ?? ''); setWebsite(c.website ?? ''); setAddress(c.address ?? '')
    setNotes(c.notes ?? ''); setRating(c.rating ?? 0); setIsPreferred(c.is_preferred)
    setShowForm(true)
  }

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim()) return
    setSaving(true)
    try {
      const supabase = createClient()
      const payload = {
        property_id: property.id,
        name: name.trim(),
        category: formCategory || null,
        phone: phone.trim() || null,
        email: email.trim() || null,
        website: website.trim() || null,
        address: address.trim() || null,
        notes: notes.trim() || null,
        rating: rating || null,
        is_preferred: isPreferred,
        created_by: userId,
      }
      if (editId) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data, error } = await (supabase as any)
          .from('contractors')
          .update(payload)
          .eq('id', editId)
          .select()
          .single()
        if (error) throw error
        setContractors((prev) => prev.map((c) => (c.id === editId ? data : c)))
        toast({ title: 'Contractor updated' })
      } else {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data, error } = await (supabase as any)
          .from('contractors')
          .insert(payload)
          .select()
          .single()
        if (error) throw error
        setContractors((prev) => [data, ...prev])
        toast({ title: 'Contractor added' })
      }
      setShowForm(false)
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete(c: Contractor) {
    const ok = await confirmDialog({
      title: 'Delete contractor',
      description: `Delete "${c.name}"? This cannot be undone.`,
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(c.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('contractors').delete().eq('id', c.id)
      setContractors((prev) => prev.filter((x) => x.id !== c.id))
      toast({ title: 'Contractor deleted' })
    } finally {
      setDeletingId(null)
    }
  }

  const filterTabs = ['all', 'preferred', ...categories]

  return (
    <>
      <PageHeader
        title="Contractors"
        description={property.name}
        action={{ label: 'Add Contractor', href: '#', onClick: openNew }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Filter tabs */}
        <div className="flex gap-2 flex-wrap">
          {filterTabs.map((tab) => (
            <button
              key={tab}
              onClick={() => setCategoryFilter(tab)}
              className={cn(
                'px-3 py-1 rounded-full text-xs font-medium border transition-colors capitalize',
                categoryFilter === tab
                  ? 'bg-primary text-white border-primary'
                  : 'border-border/50 text-muted-foreground hover:text-foreground',
              )}
            >
              {tab}
            </button>
          ))}
        </div>

        {/* Contractor cards */}
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
            <HardHat className="h-10 w-10 opacity-30" />
            <p className="text-sm">No contractors yet</p>
            <Button size="sm" onClick={openNew}><Plus className="h-4 w-4 mr-1" />Add Contractor</Button>
          </div>
        ) : (
          <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
            {filtered.map((c) => {
              const catColor = c.category ? (CATEGORY_COLORS[c.category] ?? CATEGORY_COLORS.other) : CATEGORY_COLORS.other
              return (
                <Card key={c.id} className="p-4 flex flex-col gap-3">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-center gap-2 min-w-0">
                      <div
                        className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg"
                        style={{ background: `${catColor}20`, color: catColor }}
                      >
                        <HardHat className="h-4 w-4" />
                      </div>
                      <div className="min-w-0">
                        <div className="flex items-center gap-1.5 flex-wrap">
                          <p className="font-semibold text-sm truncate">{c.name}</p>
                          {c.is_preferred && (
                            <Badge variant="neutral" size="xs" style={{ color: 'hsl(45,75%,42%)', borderColor: 'hsl(45,75%,42%)44', background: 'hsl(45,75%,42%)18' }}>
                              Preferred
                            </Badge>
                          )}
                        </div>
                        {c.category && (
                          <Badge variant="neutral" size="xs" className="capitalize mt-0.5" style={{ color: catColor, borderColor: `${catColor}44`, background: `${catColor}18` }}>
                            {c.category}
                          </Badge>
                        )}
                      </div>
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      <button onClick={() => openEdit(c)} className="p-1.5 rounded-lg hover:bg-muted transition-colors text-muted-foreground hover:text-foreground">
                        <Pencil className="h-3.5 w-3.5" />
                      </button>
                      <button
                        onClick={() => handleDelete(c)}
                        disabled={deletingId === c.id}
                        className="p-1.5 rounded-lg hover:bg-destructive/10 transition-colors text-muted-foreground hover:text-destructive"
                      >
                        {deletingId === c.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />}
                      </button>
                    </div>
                  </div>

                  {c.rating != null && c.rating > 0 && (
                    <StarRating rating={c.rating} />
                  )}

                  <div className="flex flex-col gap-1.5">
                    {c.phone && (
                      <a
                        href={`tel:${c.phone}`}
                        className="flex items-center gap-2 text-xs text-muted-foreground hover:text-foreground transition-colors"
                      >
                        <Phone className="h-3.5 w-3.5 shrink-0" />
                        {c.phone}
                      </a>
                    )}
                    {c.email && (
                      <a
                        href={`mailto:${c.email}`}
                        className="flex items-center gap-2 text-xs text-muted-foreground hover:text-foreground transition-colors truncate"
                      >
                        <Mail className="h-3.5 w-3.5 shrink-0" />
                        <span className="truncate">{c.email}</span>
                      </a>
                    )}
                    {c.website && (
                      <a
                        href={c.website.startsWith('http') ? c.website : `https://${c.website}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="flex items-center gap-2 text-xs text-muted-foreground hover:text-foreground transition-colors truncate"
                      >
                        <Globe className="h-3.5 w-3.5 shrink-0" />
                        <span className="truncate">{c.website}</span>
                      </a>
                    )}
                    {c.address && (
                      <p className="flex items-center gap-2 text-xs text-muted-foreground">
                        <MapPin className="h-3.5 w-3.5 shrink-0" />
                        {c.address}
                      </p>
                    )}
                  </div>

                  {c.notes && (
                    <p className="text-xs text-muted-foreground line-clamp-2 italic">{c.notes}</p>
                  )}
                </Card>
              )
            })}
          </div>
        )}
      </div>

      {/* Add / Edit modal */}
      {showForm && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-lg p-5 space-y-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">{editId ? 'Edit Contractor' : 'Add Contractor'}</h2>
              <button onClick={() => setShowForm(false)} className="text-muted-foreground hover:text-foreground">
                <X className="h-4 w-4" />
              </button>
            </div>
            <form onSubmit={handleSave} className="space-y-3">
              <Input placeholder="Name *" value={name} onChange={(e) => setName(e.target.value)} required />

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs text-muted-foreground mb-1 block">Category *</label>
                  <select
                    value={formCategory}
                    onChange={(e) => setFormCategory(e.target.value)}
                    className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                    required
                  >
                    {CONTRACTOR_CATEGORIES.map((c) => (
                      <option key={c} value={c}>{c.charAt(0).toUpperCase() + c.slice(1)}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="text-xs text-muted-foreground mb-1 block">Rating</label>
                  <div className="flex items-center gap-1 pt-2">
                    <StarRating rating={rating} onChange={setRating} />
                    {rating > 0 && (
                      <button type="button" onClick={() => setRating(0)} className="text-xs text-muted-foreground ml-1 hover:text-foreground">×</button>
                    )}
                  </div>
                </div>
              </div>

              <Input placeholder="Phone" value={phone} onChange={(e) => setPhone(e.target.value)} />
              <Input placeholder="Email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
              <Input placeholder="Website" value={website} onChange={(e) => setWebsite(e.target.value)} />
              <Input placeholder="Address" value={address} onChange={(e) => setAddress(e.target.value)} />

              <textarea
                placeholder="Notes (optional)"
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                rows={2}
                className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30"
              />

              <label className="flex items-center gap-2 cursor-pointer select-none">
                <input
                  type="checkbox"
                  checked={isPreferred}
                  onChange={(e) => setIsPreferred(e.target.checked)}
                  className="rounded"
                />
                <span className="text-sm">Mark as preferred contractor</span>
              </label>

              <div className="flex justify-end gap-2">
                <Button type="button" variant="ghost" size="sm" onClick={() => setShowForm(false)}>Cancel</Button>
                <Button type="submit" size="sm" disabled={saving}>
                  {saving && <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />}
                  {editId ? 'Save changes' : 'Add contractor'}
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}
