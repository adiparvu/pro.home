'use client'

import * as React from 'react'
import Link from 'next/link'
import {
  LayoutPanelLeft, Move, X, Archive, Wrench, ChevronDown, ChevronUp,
  AlertCircle, CheckCircle2, Home, Layers,
} from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import type { Room, InventoryItem, MaintenanceTask, RoomType } from '@/lib/supabase/types'

// ─── Types ────────────────────────────────────────────────────────────────────

interface SlimItem  { id: string; name: string; room_id: string | null; condition: string | null }
interface SlimTask  { id: string; title: string; room_id: string | null; status: string; priority: string }

interface DigitalTwinPageProps {
  propertyId: string
  rooms: Room[]
  items: SlimItem[]
  tasks: SlimTask[]
}

// ─── Constants ────────────────────────────────────────────────────────────────

const ROOM_TYPE_LABELS: Record<RoomType, string> = {
  bedroom: 'Bedroom', bathroom: 'Bathroom', kitchen: 'Kitchen',
  living_room: 'Living Room', dining_room: 'Dining Room', office: 'Office',
  garage: 'Garage', basement: 'Basement', attic: 'Attic',
  hallway: 'Hallway', laundry: 'Laundry', storage: 'Storage',
  garden: 'Garden', balcony: 'Balcony', terrace: 'Terrace', other: 'Other',
}

const ROOM_COLORS: Record<RoomType, string> = {
  bedroom:     'hsl(220,62%,52%)',
  bathroom:    'hsl(180,52%,42%)',
  kitchen:     'hsl(36,75%,46%)',
  living_room: 'hsl(280,52%,52%)',
  dining_room: 'hsl(22,68%,48%)',
  office:      'hsl(210,52%,48%)',
  garage:      'hsl(0,0%,46%)',
  basement:    'hsl(20,30%,42%)',
  attic:       'hsl(45,50%,44%)',
  hallway:     'hsl(200,42%,44%)',
  laundry:     'hsl(340,52%,48%)',
  storage:     'hsl(100,30%,42%)',
  garden:      'hsl(120,52%,36%)',
  balcony:     'hsl(152,52%,40%)',
  terrace:     'hsl(160,42%,42%)',
  other:       'hsl(240,20%,50%)',
}

const PRIORITY_COLORS: Record<string, string> = {
  critical: 'hsl(0,68%,52%)',
  high:     'hsl(22,68%,52%)',
  medium:   'hsl(45,75%,42%)',
  low:      'hsl(152,62%,42%)',
}

// ─── Main component ───────────────────────────────────────────────────────────

export function DigitalTwinPage({ propertyId, rooms: initialRooms, items, tasks }: DigitalTwinPageProps) {
  const [rooms, setRooms] = React.useState<Room[]>(initialRooms)
  const [activeFloor, setActiveFloor] = React.useState(0)
  const [selectedRoom, setSelectedRoom] = React.useState<Room | null>(null)
  const [editMode, setEditMode] = React.useState(false)
  const canvasRef = React.useRef<HTMLDivElement>(null)
  const dragState = React.useRef<{ roomId: string; startX: number; startY: number; origX: number; origY: number } | null>(null)

  const floors = React.useMemo(() => {
    const fs = [...new Set(rooms.map((r) => r.floor))].sort()
    return fs.length ? fs : [0]
  }, [rooms])

  const floorRooms = rooms.filter((r) => r.floor === activeFloor)
  const placedRooms = floorRooms.filter((r) => r.x_pct != null && r.y_pct != null)
  const unplacedRooms = floorRooms.filter((r) => r.x_pct == null || r.y_pct == null)

  // item + task counts per room
  const itemsByRoom = React.useMemo(() => {
    const m = new Map<string, SlimItem[]>()
    for (const item of items) {
      if (!item.room_id) continue
      if (!m.has(item.room_id)) m.set(item.room_id, [])
      m.get(item.room_id)!.push(item)
    }
    return m
  }, [items])

  const tasksByRoom = React.useMemo(() => {
    const m = new Map<string, SlimTask[]>()
    for (const task of tasks) {
      if (!task.room_id) continue
      if (!m.has(task.room_id)) m.set(task.room_id, [])
      m.get(task.room_id)!.push(task)
    }
    return m
  }, [tasks])

  // ─── Drag handlers ──────────────────────────────────────────────────────────

  function onRoomPointerDown(e: React.PointerEvent, room: Room) {
    if (!editMode) return
    e.preventDefault()
    e.stopPropagation()
    dragState.current = {
      roomId: room.id,
      startX: e.clientX,
      startY: e.clientY,
      origX: room.x_pct ?? 10,
      origY: room.y_pct ?? 10,
    }
    ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
  }

  function onRoomPointerMove(e: React.PointerEvent, room: Room) {
    if (!dragState.current || dragState.current.roomId !== room.id) return
    const canvas = canvasRef.current
    if (!canvas) return
    const rect = canvas.getBoundingClientRect()
    const dxPct = ((e.clientX - dragState.current.startX) / rect.width) * 100
    const dyPct = ((e.clientY - dragState.current.startY) / rect.height) * 100
    const newX = Math.max(0, Math.min(90, dragState.current.origX + dxPct))
    const newY = Math.max(0, Math.min(90, dragState.current.origY + dyPct))
    setRooms((prev) => prev.map((r) => r.id === room.id ? { ...r, x_pct: newX, y_pct: newY } : r))
  }

  async function onRoomPointerUp(e: React.PointerEvent, room: Room) {
    if (!dragState.current || dragState.current.roomId !== room.id) return
    dragState.current = null
    const current = rooms.find((r) => r.id === room.id)
    if (!current) return
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('rooms').update({ x_pct: current.x_pct, y_pct: current.y_pct }).eq('id', room.id)
  }

  async function placeRoom(room: Room) {
    const newX = 10 + (placedRooms.length % 4) * 22
    const newY = 10 + Math.floor(placedRooms.length / 4) * 28
    setRooms((prev) => prev.map((r) => r.id === room.id ? { ...r, x_pct: newX, y_pct: newY, width_pct: 18, height_pct: 22 } : r))
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('rooms').update({ x_pct: newX, y_pct: newY, width_pct: 18, height_pct: 22 }).eq('id', room.id)
  }

  // ─── Stats ──────────────────────────────────────────────────────────────────

  const totalItems = items.length
  const openTasks = tasks.filter((t) => t.status !== 'completed' && t.status !== 'cancelled').length

  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
      {/* Stats row */}
      <div className="grid grid-cols-3 gap-2">
        <StatChip icon={<Home className="h-3.5 w-3.5" />} label="Rooms" value={rooms.length} color="hsl(220,62%,52%)" />
        <StatChip icon={<Archive className="h-3.5 w-3.5" />} label="Items" value={totalItems} color="hsl(185,62%,38%)" />
        <StatChip icon={<Wrench className="h-3.5 w-3.5" />} label="Open tasks" value={openTasks} color={openTasks > 0 ? 'hsl(22,68%,52%)' : 'hsl(152,62%,42%)'} />
      </div>

      {/* Floor tabs + edit toggle */}
      <div className="flex items-center justify-between gap-2">
        <div className="flex gap-1">
          {floors.map((fl) => (
            <button
              key={fl}
              type="button"
              onClick={() => setActiveFloor(fl)}
              className={cn(
                'flex items-center gap-1 rounded-full px-3 py-1 text-xs font-medium transition-colors',
                activeFloor === fl ? 'bg-primary text-white' : 'glass-light text-muted-foreground hover:text-foreground'
              )}
            >
              <Layers className="h-3 w-3" />
              {fl === 0 ? 'Ground' : fl === -1 ? 'Basement' : `Floor ${fl}`}
            </button>
          ))}
        </div>
        {placedRooms.length > 0 && (
          <button
            type="button"
            onClick={() => setEditMode((v) => !v)}
            className={cn(
              'flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium transition-colors',
              editMode ? 'bg-primary text-white' : 'glass-light text-muted-foreground hover:text-foreground'
            )}
          >
            <Move className="h-3 w-3" />
            {editMode ? 'Done' : 'Arrange'}
          </button>
        )}
      </div>

      {/* Floor plan canvas */}
      <div
        ref={canvasRef}
        className="relative w-full rounded-2xl border border-border/50 glass-light overflow-hidden"
        style={{ aspectRatio: '4/3' }}
      >
        {floorRooms.length === 0 ? (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 text-center p-4">
            <LayoutPanelLeft className="h-10 w-10 text-muted-foreground" />
            <p className="text-sm font-medium text-muted-foreground">No rooms on this floor</p>
            <Link href="/property" className="text-xs text-primary hover:underline">
              Add rooms in Property settings
            </Link>
          </div>
        ) : placedRooms.length === 0 ? (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 text-center p-4">
            <LayoutPanelLeft className="h-10 w-10 text-muted-foreground" />
            <p className="text-sm font-medium text-muted-foreground">No rooms placed yet</p>
            <p className="text-xs text-muted-foreground max-w-[200px]">Tap a room below to place it on the floor plan</p>
          </div>
        ) : null}

        {/* Grid lines (subtle) */}
        <div className="absolute inset-0 opacity-[0.04]"
          style={{
            backgroundImage: 'linear-gradient(hsl(var(--foreground)) 1px, transparent 1px), linear-gradient(90deg, hsl(var(--foreground)) 1px, transparent 1px)',
            backgroundSize: '10% 10%',
          }}
        />

        {/* Placed room blocks */}
        {placedRooms.map((room) => {
          const color = ROOM_COLORS[room.room_type] ?? 'hsl(240,20%,50%)'
          const isSelected = selectedRoom?.id === room.id
          const iCount = itemsByRoom.get(room.id)?.length ?? 0
          const tCount = tasksByRoom.get(room.id)?.filter((t) => t.status !== 'completed' && t.status !== 'cancelled').length ?? 0
          return (
            <div
              key={room.id}
              className={cn(
                'absolute flex flex-col items-start justify-start p-1.5 rounded-xl border cursor-pointer select-none transition-all duration-fast',
                editMode && 'cursor-move',
                isSelected && 'z-10'
              )}
              style={{
                left: `${room.x_pct ?? 10}%`,
                top: `${room.y_pct ?? 10}%`,
                width: `${room.width_pct ?? 18}%`,
                height: `${room.height_pct ?? 22}%`,
                background: isSelected ? `${color}30` : `${color}18`,
                borderColor: isSelected ? color : `${color}50`,
                boxShadow: isSelected ? `0 0 0 2px ${color}60` : undefined,
              }}
              onClick={() => !editMode && setSelectedRoom(isSelected ? null : room)}
              onPointerDown={(e) => onRoomPointerDown(e, room)}
              onPointerMove={(e) => onRoomPointerMove(e, room)}
              onPointerUp={(e) => onRoomPointerUp(e, room)}
            >
              <p className="text-[10px] font-semibold leading-tight truncate w-full" style={{ color }}>{room.name}</p>
              <div className="flex items-center gap-1 mt-auto flex-wrap">
                {iCount > 0 && (
                  <span className="text-[9px] rounded-full px-1 py-0.5 font-medium" style={{ background: `${color}22`, color }}>
                    {iCount} items
                  </span>
                )}
                {tCount > 0 && (
                  <span className="text-[9px] rounded-full px-1 py-0.5 font-medium bg-destructive/20 text-destructive">
                    {tCount} tasks
                  </span>
                )}
              </div>
            </div>
          )
        })}
      </div>

      {/* Unplaced rooms */}
      {unplacedRooms.length > 0 && (
        <div className="flex flex-col gap-2">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            Unplaced rooms — tap to add to floor plan
          </p>
          <div className="flex gap-2 flex-wrap">
            {unplacedRooms.map((room) => {
              const color = ROOM_COLORS[room.room_type] ?? 'hsl(240,20%,50%)'
              return (
                <button
                  key={room.id}
                  type="button"
                  onClick={() => placeRoom(room)}
                  className="flex items-center gap-1.5 rounded-xl px-3 py-2 text-xs font-medium transition-all hover:scale-105"
                  style={{ background: `${color}18`, border: `1px solid ${color}40`, color }}
                >
                  <LayoutPanelLeft className="h-3 w-3" />
                  {room.name}
                </button>
              )
            })}
          </div>
        </div>
      )}

      {/* Selected room detail panel */}
      {selectedRoom && (
        <RoomDetailPanel
          room={selectedRoom}
          items={itemsByRoom.get(selectedRoom.id) ?? []}
          tasks={tasksByRoom.get(selectedRoom.id) ?? []}
          onClose={() => setSelectedRoom(null)}
        />
      )}

      {/* All rooms list */}
      <div className="flex flex-col gap-3">
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">All Rooms</p>
        {rooms.length === 0 ? (
          <div className="flex flex-col items-center gap-2 py-8 text-center rounded-2xl border border-border/50 glass-light">
            <Home className="h-7 w-7 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">No rooms yet — add them in Property settings.</p>
            <Link href="/property" className="text-xs text-primary hover:underline">Go to Property</Link>
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
            {rooms.map((room) => {
              const color = ROOM_COLORS[room.room_type] ?? 'hsl(240,20%,50%)'
              const iCount = itemsByRoom.get(room.id)?.length ?? 0
              const openTaskCount = tasksByRoom.get(room.id)?.filter((t) => t.status !== 'completed' && t.status !== 'cancelled').length ?? 0
              return (
                <button
                  key={room.id}
                  type="button"
                  onClick={() => setSelectedRoom(selectedRoom?.id === room.id ? null : room)}
                  className={cn(
                    'flex flex-col gap-2 rounded-xl p-3 text-left transition-all',
                    selectedRoom?.id === room.id ? 'ring-2' : 'glass-light hover:glass-standard'
                  )}
                  style={selectedRoom?.id === room.id ? { background: `${color}14`, '--tw-ring-color': color } as React.CSSProperties : undefined}
                >
                  <div className="flex h-9 w-9 items-center justify-center rounded-lg" style={{ background: `${color}20` }}>
                    <span className="text-lg">{getRoomEmoji(room.room_type)}</span>
                  </div>
                  <div>
                    <p className="text-xs font-semibold text-foreground truncate">{room.name}</p>
                    <p className="text-[10px] text-muted-foreground">{ROOM_TYPE_LABELS[room.room_type]}</p>
                  </div>
                  <div className="flex gap-1 flex-wrap">
                    {iCount > 0 && (
                      <span className="text-[9px] rounded-full px-1.5 py-0.5 font-medium glass-light text-muted-foreground">
                        {iCount} items
                      </span>
                    )}
                    {openTaskCount > 0 && (
                      <span className="text-[9px] rounded-full px-1.5 py-0.5 font-medium bg-destructive/15 text-destructive">
                        {openTaskCount} tasks
                      </span>
                    )}
                  </div>
                </button>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}

// ─── Room detail panel ────────────────────────────────────────────────────────

function RoomDetailPanel({ room, items, tasks, onClose }: {
  room: Room
  items: SlimItem[]
  tasks: SlimTask[]
  onClose: () => void
}) {
  const [showAllItems, setShowAllItems] = React.useState(false)
  const color = ROOM_COLORS[room.room_type] ?? 'hsl(240,20%,50%)'
  const openTasks = tasks.filter((t) => t.status !== 'completed' && t.status !== 'cancelled')
  const visibleItems = showAllItems ? items : items.slice(0, 4)

  return (
    <Card variant="default" padding="md" className="relative">
      <button
        type="button"
        onClick={onClose}
        className="absolute right-3 top-3 flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground hover:text-foreground transition-colors"
      >
        <X className="h-4 w-4" />
      </button>

      {/* Header */}
      <div className="flex items-center gap-3 pr-8">
        <div className="flex h-12 w-12 items-center justify-center rounded-xl text-2xl" style={{ background: `${color}18` }}>
          {getRoomEmoji(room.room_type)}
        </div>
        <div>
          <p className="text-base font-bold text-foreground">{room.name}</p>
          <div className="flex items-center gap-2 mt-0.5">
            <Badge variant="neutral" size="xs">{ROOM_TYPE_LABELS[room.room_type]}</Badge>
            {room.area_sqm && <span className="text-xs text-muted-foreground">{room.area_sqm} m²</span>}
            <span className="text-xs text-muted-foreground capitalize">Floor {room.floor}</span>
          </div>
        </div>
      </div>

      {/* Inventory */}
      <div className="mt-4 flex flex-col gap-2">
        <div className="flex items-center justify-between">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground flex items-center gap-1.5">
            <Archive className="h-3.5 w-3.5" />
            Inventory ({items.length})
          </p>
          <Link href={`/inventory?room=${room.id}`} className="text-xs text-primary hover:underline">View all</Link>
        </div>
        {items.length === 0 ? (
          <p className="text-xs text-muted-foreground">No items in this room</p>
        ) : (
          <>
            <div className="flex flex-col gap-1">
              {visibleItems.map((item) => (
                <div key={item.id} className="flex items-center justify-between rounded-lg glass-light px-3 py-2">
                  <p className="text-xs text-foreground truncate">{item.name}</p>
                  {item.condition && (
                    <Badge variant={item.condition === 'broken' ? 'danger' : item.condition === 'poor' ? 'warning' : 'neutral'} size="xs" className="capitalize shrink-0 ml-2">
                      {item.condition}
                    </Badge>
                  )}
                </div>
              ))}
            </div>
            {items.length > 4 && (
              <button
                type="button"
                onClick={() => setShowAllItems((v) => !v)}
                className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
              >
                {showAllItems ? <ChevronUp className="h-3 w-3" /> : <ChevronDown className="h-3 w-3" />}
                {showAllItems ? 'Show less' : `${items.length - 4} more`}
              </button>
            )}
          </>
        )}
      </div>

      {/* Open tasks */}
      {openTasks.length > 0 && (
        <div className="mt-4 flex flex-col gap-2">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground flex items-center gap-1.5">
            <Wrench className="h-3.5 w-3.5" />
            Open tasks ({openTasks.length})
          </p>
          <div className="flex flex-col gap-1">
            {openTasks.slice(0, 3).map((task) => {
              const pColor = PRIORITY_COLORS[task.priority] ?? 'hsl(var(--muted-foreground))'
              return (
                <div key={task.id} className="flex items-center gap-2 rounded-lg glass-light px-3 py-2">
                  {task.status === 'overdue'
                    ? <AlertCircle className="h-3.5 w-3.5 shrink-0 text-destructive" />
                    : <CheckCircle2 className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
                  }
                  <p className="text-xs text-foreground flex-1 truncate">{task.title}</p>
                  <span className="h-2 w-2 rounded-full shrink-0" style={{ background: pColor }} />
                </div>
              )
            })}
          </div>
          <Link href={`/maintenance?room=${room.id}`} className="text-xs text-primary hover:underline self-start">
            View all tasks
          </Link>
        </div>
      )}
    </Card>
  )
}

// ─── Stat chip ────────────────────────────────────────────────────────────────

function StatChip({ icon, label, value, color }: { icon: React.ReactNode; label: string; value: number; color: string }) {
  return (
    <div className="flex flex-col gap-1 rounded-xl glass-light px-3 py-3">
      <div className="flex items-center gap-1.5" style={{ color }}>
        {icon}
        <span className="text-[10px] uppercase tracking-wider font-semibold text-muted-foreground">{label}</span>
      </div>
      <p className="text-xl font-bold text-foreground">{value}</p>
    </div>
  )
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function getRoomEmoji(type: RoomType): string {
  const map: Record<RoomType, string> = {
    bedroom: '🛏️', bathroom: '🚿', kitchen: '🍳', living_room: '🛋️',
    dining_room: '🍽️', office: '💼', garage: '🚗', basement: '📦',
    attic: '🏠', hallway: '🚪', laundry: '👕', storage: '📦',
    garden: '🌿', balcony: '🌅', terrace: '🌤️', other: '📍',
  }
  return map[type] ?? '📍'
}
