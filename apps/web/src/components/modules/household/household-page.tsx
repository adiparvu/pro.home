'use client'

import * as React from 'react'
import {
  ShoppingCart, CheckSquare, List, ShoppingBag, Plus, X, Loader2, Trash2,
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

type ListType = 'grocery' | 'todo' | 'shopping' | 'general'

interface HouseholdList {
  id: string
  property_id: string
  name: string
  list_type: ListType
  created_by: string | null
  household_list_items: HouseholdListItem[]
}

interface HouseholdListItem {
  id: string
  list_id: string
  text: string
  quantity: string | null
  category: string | null
  checked: boolean
  checked_by: string | null
  checked_at: string | null
  sort_order: number | null
  added_by: string | null
}

interface HouseholdPageProps {
  property: Property
  userId: string
  initialLists: HouseholdList[]
}

const LIST_CONFIG: Record<ListType, { label: string; icon: React.ComponentType<{ className?: string }>; color: string }> = {
  grocery:  { label: 'Grocery',  icon: ShoppingCart, color: 'hsl(152,62%,38%)' },
  todo:     { label: 'To-Do',    icon: CheckSquare,  color: 'hsl(220,62%,52%)' },
  shopping: { label: 'Shopping', icon: ShoppingBag,  color: 'hsl(280,68%,47%)' },
  general:  { label: 'General',  icon: List,         color: 'hsl(220,52%,46%)' },
}

export function HouseholdPage({ property, userId, initialLists }: HouseholdPageProps) {
  const confirmDialog = useConfirm()
  const [lists, setLists] = React.useState<HouseholdList[]>(initialLists)
  const [activeListId, setActiveListId] = React.useState<string | null>(initialLists[0]?.id ?? null)
  const [showNewList, setShowNewList] = React.useState(false)
  const [savingList, setSavingList] = React.useState(false)
  const [newListName, setNewListName] = React.useState('')
  const [newListType, setNewListType] = React.useState<ListType>('general')

  // Add item form state
  const [newItemText, setNewItemText] = React.useState('')
  const [newItemQty, setNewItemQty] = React.useState('')
  const [savingItem, setSavingItem] = React.useState(false)

  const [togglingId, setTogglingId] = React.useState<string | null>(null)
  const [deletingItemId, setDeletingItemId] = React.useState<string | null>(null)
  const [deletingListId, setDeletingListId] = React.useState<string | null>(null)
  const [clearingChecked, setClearingChecked] = React.useState(false)

  const activeList = lists.find((l) => l.id === activeListId) ?? null

  const sortedItems = React.useMemo(() => {
    if (!activeList) return []
    return [...activeList.household_list_items].sort((a, b) => {
      if (a.checked !== b.checked) return a.checked ? 1 : -1
      return (a.sort_order ?? 0) - (b.sort_order ?? 0)
    })
  }, [activeList])

  async function handleCreateList(e: React.FormEvent) {
    e.preventDefault()
    if (!newListName.trim()) return
    setSavingList(true)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('household_lists')
        .insert({
          property_id: property.id,
          name: newListName.trim(),
          list_type: newListType,
          created_by: userId,
        })
        .select()
        .single()
      if (error) throw error
      const newList: HouseholdList = { ...data, household_list_items: [] }
      setLists((prev) => [...prev, newList])
      setActiveListId(newList.id)
      setNewListName('')
      setShowNewList(false)
      toast({ title: 'List created' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSavingList(false)
    }
  }

  async function handleDeleteList(listId: string) {
    const list = lists.find((l) => l.id === listId)
    if (!list) return
    const ok = await confirmDialog({
      title: 'Delete list',
      description: `Delete "${list.name}" and all its items?`,
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingListId(listId)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('household_lists').delete().eq('id', listId)
      setLists((prev) => prev.filter((l) => l.id !== listId))
      if (activeListId === listId) {
        const remaining = lists.filter((l) => l.id !== listId)
        setActiveListId(remaining[0]?.id ?? null)
      }
      toast({ title: 'List deleted' })
    } finally {
      setDeletingListId(null)
    }
  }

  async function handleAddItem(e: React.FormEvent) {
    e.preventDefault()
    if (!newItemText.trim() || !activeListId) return
    setSavingItem(true)
    try {
      const supabase = createClient()
      const maxOrder = activeList
        ? Math.max(0, ...activeList.household_list_items.map((i) => i.sort_order ?? 0))
        : 0
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('household_list_items')
        .insert({
          list_id: activeListId,
          text: newItemText.trim(),
          quantity: newItemQty.trim() || null,
          checked: false,
          sort_order: maxOrder + 1,
          added_by: userId,
        })
        .select()
        .single()
      if (error) throw error
      setLists((prev) => prev.map((l) =>
        l.id === activeListId
          ? { ...l, household_list_items: [...l.household_list_items, data] }
          : l
      ))
      setNewItemText('')
      setNewItemQty('')
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSavingItem(false)
    }
  }

  async function handleToggleItem(item: HouseholdListItem) {
    const newChecked = !item.checked
    // Optimistic update
    setLists((prev) => prev.map((l) =>
      l.id === activeListId
        ? {
            ...l,
            household_list_items: l.household_list_items.map((i) =>
              i.id === item.id
                ? { ...i, checked: newChecked, checked_by: userId, checked_at: new Date().toISOString() }
                : i
            ),
          }
        : l
    ))
    setTogglingId(item.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any)
        .from('household_list_items')
        .update({
          checked: newChecked,
          checked_by: newChecked ? userId : null,
          checked_at: newChecked ? new Date().toISOString() : null,
        })
        .eq('id', item.id)
    } catch (err) {
      // Revert on error
      setLists((prev) => prev.map((l) =>
        l.id === activeListId
          ? {
              ...l,
              household_list_items: l.household_list_items.map((i) =>
                i.id === item.id ? { ...i, checked: item.checked } : i
              ),
            }
          : l
      ))
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setTogglingId(null)
    }
  }

  async function handleDeleteItem(item: HouseholdListItem) {
    setDeletingItemId(item.id)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).from('household_list_items').delete().eq('id', item.id)
      setLists((prev) => prev.map((l) =>
        l.id === activeListId
          ? { ...l, household_list_items: l.household_list_items.filter((i) => i.id !== item.id) }
          : l
      ))
    } finally {
      setDeletingItemId(null)
    }
  }

  async function handleClearChecked() {
    if (!activeListId || !activeList) return
    const checkedItems = activeList.household_list_items.filter((i) => i.checked)
    if (checkedItems.length === 0) return
    setClearingChecked(true)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any)
        .from('household_list_items')
        .delete()
        .in('id', checkedItems.map((i) => i.id))
      setLists((prev) => prev.map((l) =>
        l.id === activeListId
          ? { ...l, household_list_items: l.household_list_items.filter((i) => !i.checked) }
          : l
      ))
      toast({ title: `Cleared ${checkedItems.length} item${checkedItems.length !== 1 ? 's' : ''}` })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setClearingChecked(false)
    }
  }

  const uncheckedCount = (list: HouseholdList) =>
    list.household_list_items.filter((i) => !i.checked).length

  const checkedCount = activeList?.household_list_items.filter((i) => i.checked).length ?? 0

  return (
    <>
      <PageHeader
        title="Household"
        description={property.name}
        action={{ label: 'New List', href: '#', onClick: () => setShowNewList(true) }}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* List tabs */}
        {lists.length > 0 && (
          <div className="flex gap-2 flex-wrap">
            {lists.map((l) => {
              const cfg = LIST_CONFIG[l.list_type] ?? LIST_CONFIG.general
              const uc = uncheckedCount(l)
              return (
                <button
                  key={l.id}
                  onClick={() => setActiveListId(l.id)}
                  className={cn(
                    'px-3 py-1.5 rounded-full text-xs font-medium border transition-colors flex items-center gap-1.5',
                    activeListId === l.id
                      ? 'bg-primary text-white border-primary'
                      : 'border-border/50 text-muted-foreground hover:text-foreground'
                  )}
                >
                  {l.name}
                  {uc > 0 && (
                    <span className={cn(
                      'inline-flex h-4 w-4 items-center justify-center rounded-full text-[10px] font-bold',
                      activeListId === l.id ? 'bg-white/30 text-white' : 'bg-primary/20 text-primary'
                    )}>
                      {uc}
                    </span>
                  )}
                </button>
              )
            })}
          </div>
        )}

        {lists.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
            <List className="h-10 w-10 opacity-30" />
            <p className="text-sm">No lists yet</p>
            <Button size="sm" onClick={() => setShowNewList(true)}>
              <Plus className="h-4 w-4 mr-1" />New List
            </Button>
          </div>
        ) : activeList ? (
          <>
            {/* List header */}
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                {(() => {
                  const cfg = LIST_CONFIG[activeList.list_type] ?? LIST_CONFIG.general
                  const Icon = cfg.icon
                  return (
                    <div className="flex h-7 w-7 items-center justify-center rounded-lg" style={{ background: cfg.color + '20', color: cfg.color }}>
                      <Icon className="h-3.5 w-3.5" />
                    </div>
                  )
                })()}
                <span className="text-sm font-medium">{activeList.name}</span>
                <Badge variant="neutral" className="text-[10px]">
                  {LIST_CONFIG[activeList.list_type]?.label ?? 'General'}
                </Badge>
              </div>
              <div className="flex items-center gap-2">
                {checkedCount > 0 && (
                  <Button
                    variant="ghost"
                    size="sm"
                    className="text-xs h-7 px-2"
                    onClick={handleClearChecked}
                    disabled={clearingChecked}
                  >
                    {clearingChecked ? <Loader2 className="h-3 w-3 animate-spin mr-1" /> : null}
                    Clear checked ({checkedCount})
                  </Button>
                )}
                <button
                  onClick={() => handleDeleteList(activeList.id)}
                  disabled={deletingListId === activeList.id}
                  className="p-1.5 text-muted-foreground hover:text-destructive transition-colors"
                >
                  {deletingListId === activeList.id
                    ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                    : <Trash2 className="h-3.5 w-3.5" />}
                </button>
              </div>
            </div>

            {/* Items */}
            <Card className="p-0 overflow-hidden">
              {sortedItems.length === 0 ? (
                <p className="text-sm text-muted-foreground text-center py-8">No items yet</p>
              ) : (
                <div className="divide-y divide-border/30">
                  {sortedItems.map((item) => (
                    <div
                      key={item.id}
                      className={cn('flex items-center gap-3 px-4 py-3 transition-colors', item.checked && 'opacity-50')}
                    >
                      <button
                        onClick={() => handleToggleItem(item)}
                        disabled={togglingId === item.id}
                        className={cn(
                          'flex h-5 w-5 shrink-0 items-center justify-center rounded border-2 transition-colors',
                          item.checked
                            ? 'bg-primary border-primary text-white'
                            : 'border-border hover:border-primary/50'
                        )}
                      >
                        {item.checked && <CheckSquare className="h-3 w-3" />}
                      </button>
                      <div className="flex-1 min-w-0">
                        <span className={cn('text-sm', item.checked && 'line-through')}>{item.text}</span>
                        {item.quantity && (
                          <Badge variant="neutral" className="ml-2 text-[10px] px-1.5 py-0">{item.quantity}</Badge>
                        )}
                        {item.category && (
                          <span className="ml-2 text-[10px] text-muted-foreground">{item.category}</span>
                        )}
                      </div>
                      <button
                        onClick={() => handleDeleteItem(item)}
                        disabled={deletingItemId === item.id}
                        className="shrink-0 p-1 text-muted-foreground hover:text-destructive transition-colors"
                      >
                        {deletingItemId === item.id
                          ? <Loader2 className="h-3 w-3 animate-spin" />
                          : <X className="h-3 w-3" />}
                      </button>
                    </div>
                  ))}
                </div>
              )}

              {/* Add item form */}
              <form onSubmit={handleAddItem} className="flex items-center gap-2 px-4 py-3 border-t border-border/30">
                <Input
                  placeholder="Add item..."
                  value={newItemText}
                  onChange={(e) => setNewItemText(e.target.value)}
                  className="flex-1 h-8 text-sm"
                />
                <Input
                  placeholder="Qty"
                  value={newItemQty}
                  onChange={(e) => setNewItemQty(e.target.value)}
                  className="w-16 h-8 text-sm"
                />
                <Button type="submit" size="sm" className="h-8 px-3" disabled={savingItem || !newItemText.trim()}>
                  {savingItem ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Plus className="h-3.5 w-3.5" />}
                </Button>
              </form>
            </Card>
          </>
        ) : null}
      </div>

      {/* New List Modal */}
      {showNewList && (
        <div className="fixed inset-0 z-50 flex items-end justify-center md:items-center p-4 bg-black/40 backdrop-blur-sm">
          <Card className="w-full max-w-md p-5 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold">New List</h2>
              <button onClick={() => setShowNewList(false)}>
                <X className="h-4 w-4 text-muted-foreground" />
              </button>
            </div>
            <form onSubmit={handleCreateList} className="space-y-3">
              <Input
                placeholder="List name *"
                value={newListName}
                onChange={(e) => setNewListName(e.target.value)}
                required
              />
              <select
                value={newListType}
                onChange={(e) => setNewListType(e.target.value as ListType)}
                className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
              >
                {(Object.keys(LIST_CONFIG) as ListType[]).map((t) => (
                  <option key={t} value={t}>{LIST_CONFIG[t].label}</option>
                ))}
              </select>
              <div className="flex justify-end gap-2">
                <Button type="button" variant="ghost" size="sm" onClick={() => setShowNewList(false)}>Cancel</Button>
                <Button type="submit" size="sm" disabled={savingList}>
                  {savingList && <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" />}
                  Create list
                </Button>
              </div>
            </form>
          </Card>
        </div>
      )}
    </>
  )
}
