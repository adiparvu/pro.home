'use client'

import * as React from 'react'
import { Wifi, Plus, X, Loader2, Trash2, Copy, Check, Eye, EyeOff } from 'lucide-react'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import type { Property } from '@/lib/supabase/types'

export interface SmartHomeToken {
  id: string
  property_id: string
  token: string
  label: string
  active: boolean
  last_used_at: string | null
  created_by: string | null
  created_at: string
}

interface SmartHomePageProps {
  property: Property
  userId: string
  initialTokens: SmartHomeToken[]
}

function formatDateTime(d: string | null) {
  if (!d) return 'Never'
  return new Date(d).toLocaleString('en', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function maskToken(token: string) {
  return token.slice(0, 8) + '...'
}

const WEBHOOK_CODE_SAMPLE = `POST /api/webhooks/smart-meter
Content-Type: application/json

{
  "token": "your_token_here",
  "readings": [
    { "meter_type": "electricity", "value": 1234.5, "unit": "kWh" },
    { "meter_type": "gas", "value": 567.8, "unit": "m3" }
  ]
}`

interface CreateTokenModalProps {
  onClose: () => void
  onSave: (label: string) => Promise<void>
  saving: boolean
}

function CreateTokenModal({ onClose, onSave, saving }: CreateTokenModalProps) {
  const [label, setLabel] = React.useState('')

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!label.trim()) {
      toast({ title: 'Label is required', variant: 'destructive' })
      return
    }
    await onSave(label.trim())
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end md:items-center justify-center bg-black/40 backdrop-blur-sm p-4">
      <Card className="w-full max-w-md p-6 flex flex-col gap-4 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between">
          <p className="text-base font-semibold">Create Webhook Token</p>
          <Button variant="ghost" size="icon" onClick={onClose}>
            <X className="h-4 w-4" />
          </Button>
        </div>
        <form onSubmit={handleSubmit} className="flex flex-col gap-3">
          <div className="flex flex-col gap-1">
            <label className="text-xs text-muted-foreground">Label *</label>
            <Input
              value={label}
              onChange={(e) => setLabel(e.target.value)}
              placeholder="e.g. Smart Meter 1, Raspberry Pi"
              required
            />
            <p className="text-xs text-muted-foreground">
              A descriptive name to identify this device or integration.
            </p>
          </div>
          <div className="flex gap-2 pt-2">
            <Button type="button" variant="outline" onClick={onClose} className="flex-1">
              Cancel
            </Button>
            <Button type="submit" disabled={saving} className="flex-1">
              {saving ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
              Create Token
            </Button>
          </div>
        </form>
      </Card>
    </div>
  )
}

interface TokenCardProps {
  token: SmartHomeToken
  onToggle: (id: string, active: boolean) => Promise<void>
  onDelete: (token: SmartHomeToken) => void
  toggling: boolean
}

function TokenCard({ token, onToggle, onDelete, toggling }: TokenCardProps) {
  const [copiedUrl, setCopiedUrl] = React.useState(false)
  const [copiedToken, setCopiedToken] = React.useState(false)
  const [showFull, setShowFull] = React.useState(false)

  const webhookUrl =
    typeof window !== 'undefined'
      ? `${window.location.origin}/api/webhooks/smart-meter`
      : '/api/webhooks/smart-meter'

  const copyUrl = async () => {
    await navigator.clipboard.writeText(webhookUrl)
    setCopiedUrl(true)
    setTimeout(() => setCopiedUrl(false), 2000)
  }

  const copyToken = async () => {
    await navigator.clipboard.writeText(token.token)
    setCopiedToken(true)
    setTimeout(() => setCopiedToken(false), 2000)
  }

  return (
    <Card className="p-4 flex flex-col gap-3">
      <div className="flex items-start justify-between gap-2">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <p className="text-sm font-semibold">{token.label}</p>
            <Badge
              variant="neutral"
              style={
                token.active
                  ? { background: 'hsl(152,62%,38%)22', color: 'hsl(152,62%,38%)' }
                  : { background: 'hsl(0,0%,50%)22', color: 'hsl(0,0%,50%)' }
              }
            >
              {token.active ? 'Active' : 'Inactive'}
            </Badge>
          </div>
          <p className="text-xs text-muted-foreground mt-0.5">
            Last used: {formatDateTime(token.last_used_at)}
          </p>
        </div>
        <div className="flex gap-1 shrink-0">
          <Button
            variant="outline"
            size="sm"
            onClick={() => onToggle(token.id, !token.active)}
            disabled={toggling}
            className="text-xs"
          >
            {toggling ? (
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
            ) : token.active ? (
              'Disable'
            ) : (
              'Enable'
            )}
          </Button>
          <Button variant="ghost" size="icon" onClick={() => onDelete(token)}>
            <Trash2 className="h-3.5 w-3.5 text-red-500" />
          </Button>
        </div>
      </div>

      {/* Token display */}
      <div className="flex items-center gap-2 rounded-lg bg-muted/50 px-3 py-2">
        <code className="flex-1 text-xs font-mono text-muted-foreground truncate">
          {showFull ? token.token : maskToken(token.token)}
        </code>
        <Button
          variant="ghost"
          size="icon"
          className="h-6 w-6"
          onClick={() => setShowFull((v) => !v)}
          title={showFull ? 'Hide token' : 'Show token'}
        >
          {showFull ? (
            <EyeOff className="h-3.5 w-3.5" />
          ) : (
            <Eye className="h-3.5 w-3.5" />
          )}
        </Button>
        <Button
          variant="ghost"
          size="icon"
          className="h-6 w-6"
          onClick={copyToken}
          title="Copy token"
        >
          {copiedToken ? (
            <Check className="h-3.5 w-3.5 text-green-500" />
          ) : (
            <Copy className="h-3.5 w-3.5" />
          )}
        </Button>
      </div>

      {/* Webhook URL copy */}
      <Button variant="outline" size="sm" onClick={copyUrl} className="text-xs gap-1 self-start">
        {copiedUrl ? (
          <Check className="h-3.5 w-3.5 text-green-500" />
        ) : (
          <Copy className="h-3.5 w-3.5" />
        )}
        Copy webhook URL
      </Button>
    </Card>
  )
}

export function SmartHomePage({ property, userId: _userId, initialTokens }: SmartHomePageProps) {
  const [tokens, setTokens] = React.useState<SmartHomeToken[]>(initialTokens)
  const [modalOpen, setModalOpen] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [togglingId, setTogglingId] = React.useState<string | null>(null)
  const confirm = useConfirm()

  const handleCreateToken = async (label: string) => {
    setSaving(true)
    try {
      const res = await fetch('/api/energy/smart-home/tokens', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ label }),
      })
      const data = await res.json() as SmartHomeToken | { error: string }
      if (!res.ok) {
        throw new Error('error' in data ? data.error : 'Failed to create token')
      }
      setTokens((prev) => [data as SmartHomeToken, ...prev])
      toast({ title: 'Token created' })
      setModalOpen(false)
    } catch (err) {
      toast({ title: err instanceof Error ? err.message : 'Failed', variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  const handleToggle = async (id: string, active: boolean) => {
    setTogglingId(id)
    try {
      const res = await fetch('/api/energy/smart-home/tokens', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id, active }),
      })
      const data = await res.json() as SmartHomeToken | { error: string }
      if (!res.ok) {
        throw new Error('error' in data ? data.error : 'Failed to update token')
      }
      setTokens((prev) =>
        prev.map((t) => (t.id === id ? { ...t, active } : t))
      )
      toast({ title: active ? 'Token enabled' : 'Token disabled' })
    } catch (err) {
      toast({ title: err instanceof Error ? err.message : 'Failed', variant: 'destructive' })
    } finally {
      setTogglingId(null)
    }
  }

  const handleDelete = async (token: SmartHomeToken) => {
    const ok = await confirm({
      title: 'Delete token?',
      description: `Delete "${token.label}"? Any devices using this token will stop working.`,
      confirmLabel: 'Delete',
    })
    if (!ok) return
    const res = await fetch(`/api/energy/smart-home/tokens?id=${token.id}`, {
      method: 'DELETE',
    })
    if (!res.ok) {
      toast({ title: 'Failed to delete token', variant: 'destructive' })
      return
    }
    setTokens((prev) => prev.filter((t) => t.id !== token.id))
    toast({ title: 'Token deleted' })
  }

  return (
    <>
      <PageHeader
        title="Smart Home"
        description={property.name}
        backHref="/energy"
        action={{ label: 'New Token', href: '#', onClick: () => setModalOpen(true) }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">

        {/* Token list */}
        {tokens.length === 0 ? (
          <Card className="flex flex-col items-center gap-3 p-8 text-center">
            <Wifi className="h-8 w-8 text-muted-foreground" />
            <div>
              <p className="text-sm font-medium">No webhook tokens yet</p>
              <p className="text-xs text-muted-foreground mt-1">
                Create a token to connect your smart meter or IoT device
              </p>
            </div>
            <Button onClick={() => setModalOpen(true)} size="sm">
              <Plus className="h-4 w-4 mr-1" /> Create first token
            </Button>
          </Card>
        ) : (
          <div className="flex flex-col gap-2">
            {tokens.map((token) => (
              <TokenCard
                key={token.id}
                token={token}
                onToggle={handleToggle}
                onDelete={handleDelete}
                toggling={togglingId === token.id}
              />
            ))}
          </div>
        )}

        {/* Integration docs */}
        <Card className="p-0 overflow-hidden">
          <div className="px-4 py-3 border-b border-border/30">
            <p className="text-sm font-medium">Integration Guide</p>
            <p className="text-xs text-muted-foreground">
              Send meter readings from any device or script
            </p>
          </div>
          <div className="p-4 flex flex-col gap-3">
            <p className="text-xs text-muted-foreground">
              POST meter readings to the webhook endpoint with your token in the request body.
              The endpoint accepts JSON with a{' '}
              <code className="bg-muted px-1 py-0.5 rounded text-xs font-mono">token</code> field
              and a{' '}
              <code className="bg-muted px-1 py-0.5 rounded text-xs font-mono">readings</code>{' '}
              array.
            </p>
            <div className="rounded-lg bg-muted/80 p-3 overflow-x-auto">
              <pre
                className={cn(
                  'text-xs font-mono text-foreground/80 whitespace-pre leading-relaxed'
                )}
              >
                {WEBHOOK_CODE_SAMPLE}
              </pre>
            </div>
            <div className="flex flex-col gap-1">
              <p className="text-xs font-medium">Supported meter types</p>
              <div className="flex flex-wrap gap-1.5">
                {['electricity', 'gas', 'water', 'hot_water', 'solar', 'other'].map((t) => (
                  <Badge
                    key={t}
                    variant="neutral"
                    style={{ background: 'hsl(220,52%,46%)22', color: 'hsl(220,52%,46%)' }}
                    className="text-xs"
                  >
                    {t}
                  </Badge>
                ))}
              </div>
            </div>
            <div className="flex flex-col gap-1">
              <p className="text-xs font-medium">Response</p>
              <div className="rounded-lg bg-muted/80 p-2">
                <pre className="text-xs font-mono text-foreground/70">
                  {`{ "received": 2, "property_id": "..." }`}
                </pre>
              </div>
            </div>
          </div>
        </Card>
      </div>

      {modalOpen && (
        <CreateTokenModal
          onClose={() => setModalOpen(false)}
          onSave={handleCreateToken}
          saving={saving}
        />
      )}
    </>
  )
}
