'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import {
  Archive, Tag, Calendar, DollarSign, ShieldCheck,
  Hash, FileText, AlertCircle, Pencil, Trash2, ChevronLeft,
  MapPin, Barcode, AlertTriangle, CheckCircle, TrendingDown,
} from 'lucide-react'
import type { InventoryItem, ItemCondition } from '@/lib/supabase/types'
import { createClient } from '@/lib/supabase/client'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import Link from 'next/link'

interface InventoryItemDetailProps {
  item: InventoryItem
  roomName?: string | null
}

const CONDITION_COLORS: Record<ItemCondition, string> = {
  excellent: 'hsl(152,62%,38%)',
  good:      'hsl(152,62%,48%)',
  fair:      'hsl(45,75%,42%)',
  poor:      'hsl(22,68%,45%)',
  broken:    'hsl(0,68%,44%)',
}

export function InventoryItemDetail({ item, roomName }: InventoryItemDetailProps) {
  const router = useRouter()
  const confirmDialog = useConfirm()
  const [deleting, setDeleting] = React.useState(false)
  const [recallActive, setRecallActive] = React.useState(item.recall_active)
  const [togglingRecall, setTogglingRecall] = React.useState(false)

  const warrantyExpires = item.warranty_expires ? new Date(item.warranty_expires) : null
  const warrantyValid = warrantyExpires ? warrantyExpires > new Date() : false
  const purchaseDate = item.purchase_date ? new Date(item.purchase_date) : null

  async function handleDelete() {
    const ok = await confirmDialog({
      title: 'Delete this item?',
      description: 'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeleting(true)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('inventory_items').delete().eq('id', item.id)
    toast.success('Item deleted')
    router.push('/inventory')
    router.refresh()
  }

  async function handleRecallToggle() {
    setTogglingRecall(true)
    const supabase = createClient()
    const newValue = !recallActive
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error } = await (supabase as any).from('inventory_items').update({ recall_active: newValue }).eq('id', item.id)
    if (!error) setRecallActive(newValue)
    setTogglingRecall(false)
  }

  return (
    <div className="flex flex-col">
      {/* Header */}
      <header className="glass-opaque sticky top-0 z-20 border-b border-border/50 px-4 py-4 md:px-6">
        <div className="flex items-center justify-between gap-3">
          <div className="flex items-center gap-3 min-w-0">
            <Link
              href="/inventory"
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg glass-light text-muted-foreground hover:text-foreground transition-colors focus-ring"
            >
              <ChevronLeft className="h-4 w-4" />
            </Link>
            <div className="min-w-0">
              <h1 className="truncate text-lg font-bold text-foreground">{item.name}</h1>
              {(item.brand || item.model) && (
                <p className="text-xs text-muted-foreground truncate">
                  {[item.brand, item.model].filter(Boolean).join(' · ')}
                </p>
              )}
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Button asChild variant="ghost" size="icon">
              <Link href={`/inventory/${item.id}/edit`} aria-label="Edit item">
                <Pencil className="h-4 w-4" />
              </Link>
            </Button>
            <Button variant="ghost" size="icon" onClick={handleDelete} loading={deleting} aria-label="Delete item">
              <Trash2 className="h-4 w-4 text-destructive" />
            </Button>
          </div>
        </div>
      </header>

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6">
        {/* Recall alert */}
        {recallActive && (
          <div className="flex items-center gap-3 rounded-xl border border-destructive/30 bg-destructive/10 px-4 py-3">
            <AlertCircle className="h-4 w-4 text-destructive shrink-0" />
            <p className="text-sm text-destructive font-medium flex-1">Active recall notice on this item</p>
            <Button variant="ghost" size="sm" loading={togglingRecall} onClick={handleRecallToggle} className="text-destructive hover:text-destructive shrink-0">
              Clear
            </Button>
          </div>
        )}

        {/* Photo gallery */}
        {item.photo_urls && item.photo_urls.length > 0 && (
          <div className="flex gap-2 overflow-x-auto pb-1">
            {item.photo_urls.map((url, i) => (
              <img
                key={url}
                src={url}
                alt={`${item.name} photo ${i + 1}`}
                className="h-32 w-32 shrink-0 rounded-xl object-cover border border-border"
              />
            ))}
          </div>
        )}

        {/* Status badges */}
        <div className="flex flex-wrap gap-2">
          {item.condition && (
            <Badge
              variant="neutral"
              size="sm"
              className="capitalize"
              style={{ color: CONDITION_COLORS[item.condition], borderColor: `${CONDITION_COLORS[item.condition]}44`, background: `${CONDITION_COLORS[item.condition]}18` }}
            >
              {item.condition}
            </Badge>
          )}
          {item.category && <Badge variant="neutral" size="sm">{item.category}</Badge>}
          {roomName && (
            <Badge variant="neutral" size="sm">
              <MapPin className="h-3 w-3 mr-1" />
              {roomName}
            </Badge>
          )}
          {warrantyExpires && (
            <Badge variant={warrantyValid ? 'success' : 'danger'} size="sm">
              {warrantyValid ? 'Warranty valid' : 'Warranty expired'}
            </Badge>
          )}
        </div>

        {/* Details grid */}
        <Card variant="default" padding="md">
          <div className="flex flex-col divide-y divide-border/40">
            {item.serial_number && (
              <DetailRow icon={Hash} label="Serial number" value={item.serial_number} />
            )}
            {item.barcode && (
              <DetailRow icon={Barcode} label="Barcode" value={item.barcode} />
            )}
            {purchaseDate && (
              <DetailRow
                icon={Calendar}
                label="Purchased"
                value={purchaseDate.toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}
              />
            )}
            {item.purchase_price != null && (
              <DetailRow
                icon={DollarSign}
                label="Purchase price"
                value={`${item.purchase_currency ?? 'EUR'} ${item.purchase_price.toLocaleString()}`}
              />
            )}
            {item.current_value != null && (
              <DetailRow
                icon={TrendingDown}
                label="Current value"
                value={`${item.purchase_currency ?? 'EUR'} ${item.current_value.toLocaleString()}`}
              />
            )}
            {warrantyExpires && (
              <DetailRow
                icon={ShieldCheck}
                label="Warranty expires"
                value={warrantyExpires.toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}
                valueColor={warrantyValid ? 'hsl(152,62%,48%)' : 'hsl(0,68%,52%)'}
              />
            )}
            {item.warranty_provider && (
              <DetailRow icon={ShieldCheck} label="Warranty provider" value={item.warranty_provider} />
            )}
            {item.manual_url && (
              <DetailRow icon={FileText} label="Manual">
                <a
                  href={item.manual_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-sm text-primary hover:underline truncate max-w-[200px]"
                >
                  View manual
                </a>
              </DetailRow>
            )}
            {item.tags && item.tags.length > 0 && (
              <DetailRow icon={Tag} label="Tags">
                <div className="flex flex-wrap gap-1 justify-end">
                  {item.tags.map((t) => (
                    <span key={t} className="rounded-full glass-light px-2 py-0.5 text-xs text-muted-foreground">{t}</span>
                  ))}
                </div>
              </DetailRow>
            )}
          </div>
        </Card>

        {/* Notes */}
        {item.notes && (
          <Card variant="default" padding="md">
            <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">Notes</p>
            <p className="text-sm text-foreground whitespace-pre-wrap leading-relaxed">{item.notes}</p>
          </Card>
        )}

        {/* Recall toggle */}
        {!recallActive && (
          <div className="rounded-2xl border border-border/30 bg-transparent p-4">
            <p className="text-xs font-medium text-muted-foreground mb-2">Safety</p>
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-foreground">Recall notice</p>
                <p className="text-xs text-muted-foreground">Mark if this item has an active safety recall</p>
              </div>
              <Button variant="ghost" size="sm" loading={togglingRecall} onClick={handleRecallToggle} className="text-warning hover:text-warning shrink-0">
                <AlertTriangle className="h-3.5 w-3.5" />
                Flag recall
              </Button>
            </div>
          </div>
        )}

        {/* Empty state */}
        {!item.serial_number && !item.purchase_price && !item.warranty_expires && !item.notes && !item.barcode && !item.current_value && (
          <div className="flex flex-col items-center gap-3 py-10 text-center">
            <Archive className="h-8 w-8 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">No additional details — tap edit to add more</p>
          </div>
        )}
      </div>
    </div>
  )
}

function DetailRow({
  icon: Icon,
  label,
  value,
  valueColor,
  children,
}: {
  icon: React.ComponentType<{ className?: string }>
  label: string
  value?: string
  valueColor?: string
  children?: React.ReactNode
}) {
  return (
    <div className="flex items-start gap-3 py-3 first:pt-0 last:pb-0">
      <Icon className="h-4 w-4 shrink-0 text-muted-foreground mt-0.5" />
      <div className="flex flex-1 items-start justify-between gap-4">
        <span className="text-sm text-muted-foreground">{label}</span>
        {children ?? (
          <span className="text-sm font-medium text-right" style={valueColor ? { color: valueColor } : undefined}>
            {value}
          </span>
        )}
      </div>
    </div>
  )
}
