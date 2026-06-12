'use client'

import * as React from 'react'
import {
  ClipboardList,
  CheckSquare,
  Square,
  ChevronDown,
  ChevronUp,
  Plus,
  Trash2,
  Loader2,
  X,
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

interface MoveChecklist {
  id: string
  property_id: string
  type: 'move_in' | 'move_out'
  tenant_name: string
  move_date: string | null
  status: 'draft' | 'in_progress' | 'completed' | 'signed'
  notes: string | null
  created_by: string | null
  created_at: string
}

interface MoveChecklistItem {
  id: string
  checklist_id: string
  room: string | null
  item: string
  condition: 'excellent' | 'good' | 'fair' | 'poor' | 'damaged' | 'missing' | null
  photo_urls: string[] | null
  notes: string | null
  checked: boolean
  sort_order: number | null
}

interface MoveChecklistPageProps {
  property: Property
  userId: string
  initialChecklists: MoveChecklist[]
  initialItems: MoveChecklistItem[]
}

const CONDITION_COLORS: Record<string, string> = {
  excellent: 'hsl(152,62%,42%)',
  good: 'hsl(210,75%,42%)',
  fair: 'hsl(45,75%,42%)',
  poor: 'hsl(22,68%,45%)',
  damaged: 'hsl(0,68%,44%)',
  missing: 'hsl(0,0%,50%)',
}

const STATUS_COLORS: Record<string, string> = {
  draft: 'hsl(0,0%,50%)',
  in_progress: 'hsl(210,75%,42%)',
  completed: 'hsl(152,62%,42%)',
  signed: 'hsl(270,60%,50%)',
}

function fmtDate(d: string | null) {
  if (!d) return '—'
  return new Date(d).toLocaleDateString('en', { day: 'numeric', month: 'short', year: 'numeric' })
}

function buildItemsByChecklist(items: MoveChecklistItem[]): Record<string, MoveChecklistItem[]> {
  const map: Record<string, MoveChecklistItem[]> = {}
  for (const item of items) {
    if (!map[item.checklist_id]) map[item.checklist_id] = []
    map[item.checklist_id]!.push(item)
  }
  return map
}

export function MoveChecklistPage({ property, userId, initialChecklists, initialItems }: MoveChecklistPageProps) {
  const confirmDialog = useConfirm()
  const [checklists, setChecklists] = React.useState<MoveChecklist[]>(initialChecklists)
  const [itemsByChecklist, setItemsByChecklist] = React.useState<Record<string, MoveChecklistItem[]>>(
    () => buildItemsByChecklist(initialItems)
  )
  const [expandedId, setExpandedId] = React.useState<string | null>(null)
  const [showForm, setShowForm] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)
  const [completingId, setCompletingId] = React.useState<string | null>(null)

  // New checklist form state
  const [formType, setFormType] = React.useState<'move_in' | 'move_out'>('move_in')
  const [formTenantName, setFormTenantName] = React.useState('')
  const [formMoveDate, setFormMoveDate] = React.useState('')
  const [formNotes, setFormNotes] = React.useState('')

  function openNewForm() {
    setFormType('move_in')
    setFormTenantName('')
    setFormMoveDate('')
    setFormNotes('')
    setShowForm(true)
  }

  async function handleCreateChecklist(e: React.FormEvent) {
    e.preventDefault()
    if (!formTenantName.trim()) return
    setSaving(true)
    try {
      const supabase = createClient()
      const payload = {
        property_id: property.id,
        type: formType,
        tenant_name: formTenantName.trim(),
        move_date: formMoveDate || null,
        status: 'draft' as const,
        notes: formNotes.trim() || null,
        created_by: userId,
      }
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('move_checklists')
        .insert(payload)
        .select()
        .single()
      if (error) throw error
      setChecklists((prev) => [data, ...prev])
      setShowForm(false)
      toast({ title: 'Checklist created' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete(checklist: MoveChecklist) {
    const ok = await confirmDialog({
      title: 'Delete checklist',
      description: `Delete checklist for "${checklist.tenant_name}"? This cannot be undone.`,
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(checklist.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('move_checklist_items').delete().eq('checklist_id', checklist.id)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('move_checklists').delete().eq('id', checklist.id)
      setChecklists((prev) => prev.filter((c) => c.id !== checklist.id))
      setItemsByChecklist((prev) => {
        const next = { ...prev }
        delete next[checklist.id]
        return next
      })
      if (expandedId === checklist.id) setExpandedId(null)
      toast({ title: 'Checklist deleted' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setDeletingId(null)
    }
  }

  async function handleMarkComplete(checklist: MoveChecklist) {
    setCompletingId(checklist.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('move_checklists')
        .update({ status: 'completed' })
        .eq('id', checklist.id)
        .select()
        .single()
      if (error) throw error
      setChecklists((prev) => prev.map((c) => (c.id === checklist.id ? data : c)))
      toast({ title: 'Marked as completed' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setCompletingId(null)
    }
  }

  async function handleToggleItem(item: MoveChecklistItem) {
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data, error } = await (supabase as any)
      .from('move_checklist_items')
      .update({ checked: !item.checked })
      .eq('id', item.id)
      .select()
      .single()
    if (error) {
      toast({ title: 'Error', description: String(error), variant: 'destructive' })
      return
    }
    setItemsByChecklist((prev) => ({
      ...prev,
      [item.checklist_id]: (prev[item.checklist_id] ?? []).map((i) =>
        i.id === item.id ? data : i
      ),
    }))
  }

  async function handleAddItem(
    checklistId: string,
    room: string,
    itemText: string,
    condition: string
  ) {
    const supabase = createClient()
    const currentItems = itemsByChecklist[checklistId] ?? []
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data, error } = await (supabase as any)
      .from('move_checklist_items')
      .insert({
        checklist_id: checklistId,
        room: room.trim() || null,
        item: itemText.trim(),
        condition: condition || null,
        checked: false,
        sort_order: currentItems.length,
      })
      .select()
      .single()
    if (error) {
      toast({ title: 'Error', description: String(error), variant: 'destructive' })
      return false
    }
    setItemsByChecklist((prev) => ({
      ...prev,
      [checklistId]: [...(prev[checklistId] ?? []), data],
    }))
    return true
  }

  return (
    <>
      <PageHeader
        title="Move Checklists"
        description={property.name}
        backHref="/maintenance"
        action={{ label: 'New Checklist', href: '#', onClick: openNewForm }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6">
        {checklists.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-center">
            <div className="flex h-14 w-14 items-center justify-center rounded-2xl glass-standard">
              <ClipboardList className="h-7 w-7 text-muted-foreground" />
            </div>
            <p className="font-semibold text-foreground">No checklists yet</p>
            <p className="text-sm text-muted-foreground max-w-[200px]">
              Track property condition at move-in and move-out
            </p>
            <Button size="sm" onClick={openNewForm}>
              <Plus className="h-4 w-4 mr-1" />
              New Checklist
            </Button>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {checklists.map((checklist) => {
              const items = itemsByChecklist[checklist.id] ?? []
              const checkedCount = items.filter((i) => i.checked).length
              const isExpanded = expandedId === checklist.id

              return (
                <ChecklistCard
                  key={checklist.id}
                  checklist={checklist}
                  items={items}
                  checkedCount={checkedCount}
                  isExpanded={isExpanded}
                  deleting={deletingId === checklist.id}
                  completing={completingId === checklist.id}
                  onToggleExpand={() => setExpandedId(isExpanded ? null : checklist.id)}
                  onDelete={() => handleDelete(checklist)}
                  onMarkComplete={() => handleMarkComplete(checklist)}
                  onToggleItem={handleToggleItem}
                  onAddItem={handleAddItem}
                />
              )
            })}
          </div>
        )}
      </div>

      {/* New checklist modal */}
      {showForm && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-lg p-5 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">New Move Checklist</h2>
              <button
                onClick={() => setShowForm(false)}
                className="text-muted-foreground hover:text-foreground"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
            <form onSubmit={handleCreateChecklist} className="space-y-3">
              <div>
                <label className="text-xs text-muted-foreground mb-1 block">Type</label>
                <select
                  value={formType}
                  onChange={(e) => setFormType(e.target.value as 'move_in' | 'move_out')}
                  className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                >
                  <option value="move_in">Move In</option>
                  <option value="move_out">Move Out</option>
                </select>
              </div>
              <Input
                placeholder="Tenant name *"
                value={formTenantName}
                onChange={(e) => setFormTenantName(e.target.value)}
                required
              />
              <div>
                <label className="text-xs text-muted-foreground mb-1 block">Move date</label>
                <Input
                  type="date"
                  value={formMoveDate}
                  onChange={(e) => setFormMoveDate(e.target.value)}
                />
              </div>
              <textarea
                placeholder="Notes (optional)"
                value={formNotes}
                onChange={(e) => setFormNotes(e.target.value)}
                rows={2}
                className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <div className="flex justify-end gap-2">
                <Button type="button" variant="ghost" size="sm" onClick={() => setShowForm(false)}>
                  Cancel
                </Button>
                <Button type="submit" size="sm" disabled={saving}>
                  {saving && <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />}
                  Create checklist
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}

interface ChecklistCardProps {
  checklist: MoveChecklist
  items: MoveChecklistItem[]
  checkedCount: number
  isExpanded: boolean
  deleting: boolean
  completing: boolean
  onToggleExpand: () => void
  onDelete: () => void
  onMarkComplete: () => void
  onToggleItem: (item: MoveChecklistItem) => void
  onAddItem: (checklistId: string, room: string, item: string, condition: string) => Promise<boolean>
}

function ChecklistCard({
  checklist,
  items,
  checkedCount,
  isExpanded,
  deleting,
  completing,
  onToggleExpand,
  onDelete,
  onMarkComplete,
  onToggleItem,
  onAddItem,
}: ChecklistCardProps) {
  const typeColor = checklist.type === 'move_in' ? 'hsl(152,62%,42%)' : 'hsl(22,68%,45%)'
  const typeLabel = checklist.type === 'move_in' ? 'MOVE IN' : 'MOVE OUT'
  const statusColor = STATUS_COLORS[checklist.status] ?? 'hsl(0,0%,50%)'
  const statusLabel = checklist.status.replace('_', ' ')
  const canComplete = checklist.status !== 'completed' && checklist.status !== 'signed'

  // Group items by room
  const rooms = React.useMemo(() => {
    const map = new Map<string, MoveChecklistItem[]>()
    for (const item of items) {
      const key = item.room ?? ''
      if (!map.has(key)) map.set(key, [])
      map.get(key)!.push(item)
    }
    return map
  }, [items])

  return (
    <Card className="overflow-hidden">
      {/* Card header row */}
      <div className="flex items-start gap-3 p-4">
        {/* Type icon */}
        <div
          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl"
          style={{ background: `${typeColor}20`, color: typeColor }}
        >
          <ClipboardList className="h-4 w-4" />
        </div>

        {/* Main info */}
        <div className="flex-1 min-w-0">
          <div className="flex flex-wrap items-center gap-1.5 mb-0.5">
            <span
              className="text-[10px] font-bold tracking-wider px-1.5 py-0.5 rounded-md"
              style={{ background: `${typeColor}20`, color: typeColor }}
            >
              {typeLabel}
            </span>
            <Badge
              variant="neutral"
              size="xs"
              className="capitalize"
              style={{ color: statusColor, borderColor: `${statusColor}44`, background: `${statusColor}18` }}
            >
              {statusLabel}
            </Badge>
          </div>
          <p className="font-semibold text-sm truncate">{checklist.tenant_name}</p>
          <div className="flex flex-wrap items-center gap-2 mt-0.5">
            {checklist.move_date && (
              <span className="text-xs text-muted-foreground">{fmtDate(checklist.move_date)}</span>
            )}
            <span className="text-xs text-muted-foreground">
              {checkedCount}/{items.length} items
            </span>
          </div>
        </div>

        {/* Actions */}
        <div className="flex items-center gap-1 shrink-0">
          <button
            type="button"
            onClick={onToggleExpand}
            className="flex h-8 w-8 items-center justify-center rounded-lg text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
          >
            {isExpanded ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
          </button>
          <button
            type="button"
            onClick={onDelete}
            disabled={deleting}
            className="flex h-8 w-8 items-center justify-center rounded-lg text-muted-foreground hover:text-destructive hover:bg-destructive/10 transition-colors disabled:opacity-50"
          >
            {deleting ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />}
          </button>
        </div>
      </div>

      {/* Expanded content */}
      {isExpanded && (
        <div className="border-t border-border/40 px-4 pb-4 pt-3 space-y-4">
          {/* Items grouped by room */}
          {items.length === 0 ? (
            <p className="text-xs text-muted-foreground py-2">No items yet. Add one below.</p>
          ) : (
            <div className="space-y-3">
              {[...rooms.entries()].map(([room, roomItems]) => (
                <div key={room || '__no_room__'}>
                  {room && (
                    <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground mb-1.5">
                      {room}
                    </p>
                  )}
                  <div className="space-y-1">
                    {roomItems.map((item) => (
                      <ItemRow key={item.id} item={item} onToggle={() => onToggleItem(item)} />
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}

          {/* Add item inline form */}
          <AddItemForm checklistId={checklist.id} onAdd={onAddItem} />

          {/* Mark complete */}
          {canComplete && (
            <div className="flex justify-end pt-1">
              <Button
                size="sm"
                variant="ghost"
                onClick={onMarkComplete}
                disabled={completing}
                className="text-[hsl(152,62%,42%)] hover:bg-[hsl(152,62%,42%)]/10"
              >
                {completing && <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />}
                Mark complete
              </Button>
            </div>
          )}
        </div>
      )}
    </Card>
  )
}

function ItemRow({ item, onToggle }: { item: MoveChecklistItem; onToggle: () => void }) {
  const condColor = item.condition ? (CONDITION_COLORS[item.condition] ?? 'hsl(0,0%,50%)') : null

  return (
    <div className="flex items-start gap-2 py-1">
      <button
        type="button"
        onClick={onToggle}
        className="mt-0.5 shrink-0 text-muted-foreground hover:text-primary transition-colors focus:outline-none"
      >
        {item.checked ? (
          <CheckSquare className="h-4 w-4 text-primary" />
        ) : (
          <Square className="h-4 w-4" />
        )}
      </button>
      <div className="flex-1 min-w-0">
        <div className="flex flex-wrap items-center gap-1.5">
          {item.room && (
            <Badge variant="neutral" size="xs" className="shrink-0">{item.room}</Badge>
          )}
          <span className={cn('text-sm', item.checked && 'line-through text-muted-foreground')}>
            {item.item}
          </span>
          {item.condition && condColor && (
            <Badge
              variant="neutral"
              size="xs"
              className="capitalize shrink-0"
              style={{ color: condColor, borderColor: `${condColor}44`, background: `${condColor}18` }}
            >
              {item.condition}
            </Badge>
          )}
        </div>
        {item.notes && (
          <p className="text-xs text-muted-foreground mt-0.5">{item.notes}</p>
        )}
      </div>
    </div>
  )
}

const CONDITIONS = ['excellent', 'good', 'fair', 'poor', 'damaged', 'missing']

function AddItemForm({
  checklistId,
  onAdd,
}: {
  checklistId: string
  onAdd: (checklistId: string, room: string, item: string, condition: string) => Promise<boolean>
}) {
  const [room, setRoom] = React.useState('')
  const [itemText, setItemText] = React.useState('')
  const [condition, setCondition] = React.useState('')
  const [adding, setAdding] = React.useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!itemText.trim()) return
    setAdding(true)
    const ok = await onAdd(checklistId, room, itemText, condition)
    if (ok) {
      setRoom('')
      setItemText('')
      setCondition('')
    }
    setAdding(false)
  }

  return (
    <form onSubmit={handleSubmit} className="flex flex-wrap gap-2 pt-1">
      <Input
        placeholder="Room (optional)"
        value={room}
        onChange={(e) => setRoom(e.target.value)}
        className="w-32 flex-none text-sm"
      />
      <Input
        placeholder="Item *"
        value={itemText}
        onChange={(e) => setItemText(e.target.value)}
        className="flex-1 min-w-[120px] text-sm"
        required
      />
      <select
        value={condition}
        onChange={(e) => setCondition(e.target.value)}
        className="rounded-xl border border-border/50 bg-background/50 px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
      >
        <option value="">Condition</option>
        {CONDITIONS.map((c) => (
          <option key={c} value={c}>{c.charAt(0).toUpperCase() + c.slice(1)}</option>
        ))}
      </select>
      <Button type="submit" size="sm" disabled={adding || !itemText.trim()}>
        {adding ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Plus className="h-3.5 w-3.5" />}
        Add
      </Button>
    </form>
  )
}
