'use client'

import * as React from 'react'
import { KeyRound, Plus, X, Loader2, Trash2, Copy, Check, Clock, QrCode } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import type { Property } from '@/lib/supabase/types'

interface TempAccessCode {
  id: string
  property_id: string
  token: string
  purpose: string | null
  created_by: string | null
  expires_at: string | null
  scanned_at: string | null
  scanned_count: number
  max_scans: number
  notes: string | null
  created_at: string
}

interface AccessPageProps {
  property: Property
  userId: string
  initialCodes: TempAccessCode[]
}

const EXPIRES_OPTIONS = [
  { label: '1 hour', value: '1h', ms: 1 * 60 * 60 * 1000 },
  { label: '4 hours', value: '4h', ms: 4 * 60 * 60 * 1000 },
  { label: '24 hours', value: '24h', ms: 24 * 60 * 60 * 1000 },
  { label: '72 hours', value: '72h', ms: 72 * 60 * 60 * 1000 },
  { label: '7 days', value: '7d', ms: 7 * 24 * 60 * 60 * 1000 },
]

const MAX_SCANS_OPTIONS = [
  { label: '1 scan', value: '1' },
  { label: '3 scans', value: '3' },
  { label: 'Unlimited', value: '-1' },
]

function getStatus(code: TempAccessCode): { label: string; color: string } {
  const now = new Date()
  if (code.expires_at && new Date(code.expires_at) < now) {
    return { label: 'Expired', color: 'hsl(0,68%,44%)' }
  }
  if (code.max_scans !== -1 && code.scanned_count >= code.max_scans) {
    return { label: 'Used up', color: 'hsl(0,68%,44%)' }
  }
  return { label: 'Active', color: 'hsl(152,62%,38%)' }
}

function relativeExpiry(expiresAt: string | null): string {
  if (!expiresAt) return 'No expiry'
  const diff = new Date(expiresAt).getTime() - Date.now()
  if (diff < 0) return 'Expired'
  const mins = Math.floor(diff / 60000)
  if (mins < 60) return `Expires in ${mins}m`
  const hours = Math.floor(diff / 3600000)
  if (hours < 24) return `Expires in ${hours}h`
  const days = Math.floor(diff / 86400000)
  return `Expires in ${days}d`
}

export function AccessPage({ property, userId, initialCodes }: AccessPageProps) {
  const confirmDialog = useConfirm()
  const [codes, setCodes] = React.useState<TempAccessCode[]>(initialCodes)
  const [showForm, setShowForm] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [newToken, setNewToken] = React.useState<string | null>(null)
  const [copiedId, setCopiedId] = React.useState<string | null>(null)

  // Form fields
  const [purpose, setPurpose] = React.useState('')
  const [expiresIn, setExpiresIn] = React.useState('24h')
  const [maxScans, setMaxScans] = React.useState('1')
  const [notes, setNotes] = React.useState('')

  const selectCls = 'w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30'

  function openNew() {
    setPurpose('')
    setExpiresIn('24h')
    setMaxScans('1')
    setNotes('')
    setNewToken(null)
    setShowForm(true)
  }

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault()
    if (!purpose.trim()) return
    setSaving(true)
    try {
      const supabase = createClient()
      const expiresOpt = EXPIRES_OPTIONS.find((o) => o.value === expiresIn)
      const expiresAt = expiresOpt ? new Date(Date.now() + expiresOpt.ms).toISOString() : null
      const token = Array.from(crypto.getRandomValues(new Uint8Array(16)))
        .map((b) => b.toString(16).padStart(2, '0'))
        .join('')

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('temp_access_codes')
        .insert({
          property_id: property.id,
          token,
          purpose: purpose.trim(),
          created_by: userId,
          expires_at: expiresAt,
          max_scans: parseInt(maxScans),
          scanned_count: 0,
          notes: notes.trim() || null,
        })
        .select()
        .single()
      if (error) throw error
      setCodes((prev) => [data, ...prev])
      setNewToken(data.token)
      toast({ title: 'Access code created' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete(code: TempAccessCode) {
    const ok = await confirmDialog({
      title: 'Delete access code',
      description: `Delete access code for "${code.purpose ?? 'Unnamed'}"?`,
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(code.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('temp_access_codes').delete().eq('id', code.id)
      setCodes((prev) => prev.filter((c) => c.id !== code.id))
      if (newToken === code.token) setNewToken(null)
    } finally {
      setDeletingId(null)
    }
  }

  async function deleteExpired() {
    const expiredIds = codes
      .filter((c) => {
        const { label } = getStatus(c)
        return label === 'Expired' || label === 'Used up'
      })
      .map((c) => c.id)
    if (expiredIds.length === 0) return

    const ok = await confirmDialog({
      title: 'Clear expired codes',
      description: `Remove ${expiredIds.length} expired/used code(s)?`,
      confirmLabel: 'Clear',
      destructive: true,
    })
    if (!ok) return
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('temp_access_codes').delete().in('id', expiredIds)
    setCodes((prev) => prev.filter((c) => !expiredIds.includes(c.id)))
  }

  const appUrl = process.env.NEXT_PUBLIC_APP_URL ?? ''

  function copyLink(token: string, codeId: string) {
    const url = `${appUrl}/access/${token}`
    void navigator.clipboard.writeText(url)
    setCopiedId(codeId)
    setTimeout(() => setCopiedId(null), 2000)
  }

  const expiredCount = codes.filter((c) => {
    const { label } = getStatus(c)
    return label === 'Expired' || label === 'Used up'
  }).length

  return (
    <>
      <PageHeader
        title="Access Codes"
        description={property.name}
        backHref="/more"
        action={{ label: 'New access code', href: '#', onClick: openNew }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {expiredCount > 0 && (
          <div className="flex justify-end">
            <Button variant="ghost" size="sm" onClick={deleteExpired} className="text-xs text-muted-foreground">
              <Trash2 className="h-3.5 w-3.5 mr-1" />
              Clear {expiredCount} expired
            </Button>
          </div>
        )}

        {codes.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
            <KeyRound className="h-10 w-10 opacity-30" />
            <p className="text-sm">No access codes yet</p>
            <Button size="sm" onClick={openNew}><Plus className="h-4 w-4 mr-1" />New access code</Button>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {codes.map((code) => {
              const status = getStatus(code)
              return (
                <Card key={code.id} className="p-4">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-start gap-3 flex-1 min-w-0">
                      <div
                        className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg mt-0.5"
                        style={{ background: status.color + '20', color: status.color }}
                      >
                        <KeyRound className="h-4 w-4" />
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2 flex-wrap">
                          <p className="font-semibold text-sm">{code.purpose ?? 'Access code'}</p>
                          <Badge variant="neutral" style={{ borderColor: status.color + '60', color: status.color }}>
                            {status.label}
                          </Badge>
                        </div>
                        <div className="flex items-center gap-3 mt-1 text-xs text-muted-foreground flex-wrap">
                          <span className="flex items-center gap-1">
                            <Clock className="h-3 w-3" />
                            {relativeExpiry(code.expires_at)}
                          </span>
                          <span>
                            {code.max_scans === -1
                              ? `${code.scanned_count} scans`
                              : `${code.scanned_count}/${code.max_scans} scans`}
                          </span>
                        </div>
                        {code.notes && (
                          <p className="text-xs text-muted-foreground mt-1">{code.notes}</p>
                        )}
                      </div>
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      <button
                        onClick={() => copyLink(code.token, code.id)}
                        className="p-1.5 rounded-lg hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
                        title="Copy link"
                      >
                        {copiedId === code.id ? <Check className="h-3.5 w-3.5 text-green-600" /> : <Copy className="h-3.5 w-3.5" />}
                      </button>
                      <button
                        onClick={() => handleDelete(code)}
                        disabled={deletingId === code.id}
                        className="p-1.5 rounded-lg hover:bg-destructive/10 transition-colors text-muted-foreground hover:text-destructive"
                      >
                        {deletingId === code.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />}
                      </button>
                    </div>
                  </div>

                  {/* Inline QR for the newly created code */}
                  {newToken === code.token && (
                    <div className="mt-4 pt-4 border-t border-border/30 flex flex-col items-center gap-3">
                      <p className="text-xs text-muted-foreground font-medium flex items-center gap-1.5">
                        <QrCode className="h-3.5 w-3.5" />
                        QR Code — share or scan
                      </p>
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img
                        src={`/api/qr/access/${code.token}`}
                        alt="Access QR code"
                        className="w-40 h-40 rounded-xl border border-border/30"
                      />
                      <p className="text-xs text-muted-foreground break-all text-center max-w-xs">
                        {appUrl}/access/{code.token}
                      </p>
                    </div>
                  )}
                </Card>
              )
            })}
          </div>
        )}
      </div>

      {/* Create modal */}
      {showForm && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-md p-5 space-y-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">{newToken ? 'Access Code Created' : 'New Access Code'}</h2>
              <button onClick={() => setShowForm(false)}>
                <X className="h-4 w-4 text-muted-foreground" />
              </button>
            </div>

            {newToken ? (
              <div className="flex flex-col items-center gap-4">
                <p className="text-sm text-muted-foreground text-center">Scan or share this QR code to grant access.</p>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={`/api/qr/access/${newToken}`}
                  alt="Access QR code"
                  className="w-48 h-48 rounded-2xl border border-border/30"
                />
                <p className="text-xs text-muted-foreground break-all text-center">
                  {appUrl}/access/{newToken}
                </p>
                <div className="flex gap-2 w-full">
                  <Button
                    className="flex-1"
                    variant="secondary"
                    size="sm"
                    onClick={() => {
                      void navigator.clipboard.writeText(`${appUrl}/access/${newToken}`)
                      toast({ title: 'Link copied' })
                    }}
                  >
                    <Copy className="h-3.5 w-3.5 mr-1" />
                    Copy link
                  </Button>
                  <Button className="flex-1" size="sm" onClick={() => setShowForm(false)}>Done</Button>
                </div>
              </div>
            ) : (
              <form onSubmit={handleCreate} className="space-y-3">
                <Input
                  placeholder="Purpose (e.g. Cleaner, Delivery) *"
                  value={purpose}
                  onChange={(e) => setPurpose(e.target.value)}
                  required
                />
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="text-xs text-muted-foreground">Expires in</label>
                    <select value={expiresIn} onChange={(e) => setExpiresIn(e.target.value)} className={selectCls}>
                      {EXPIRES_OPTIONS.map((o) => (
                        <option key={o.value} value={o.value}>{o.label}</option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label className="text-xs text-muted-foreground">Max scans</label>
                    <select value={maxScans} onChange={(e) => setMaxScans(e.target.value)} className={selectCls}>
                      {MAX_SCANS_OPTIONS.map((o) => (
                        <option key={o.value} value={o.value}>{o.label}</option>
                      ))}
                    </select>
                  </div>
                </div>
                <textarea
                  placeholder="Notes (optional)"
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  rows={2}
                  className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30"
                />
                <div className="flex justify-end gap-2">
                  <Button type="button" variant="ghost" size="sm" onClick={() => setShowForm(false)}>Cancel</Button>
                  <Button type="submit" size="sm" disabled={saving}>
                    {saving && <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />}
                    Create code
                  </Button>
                </div>
              </form>
            )}
          </Card>
        </div>
      )}
    </>
  )
}
