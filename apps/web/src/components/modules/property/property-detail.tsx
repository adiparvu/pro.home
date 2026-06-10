'use client'

import * as React from 'react'
import Link from 'next/link'
import {
  Building2, MapPin, Calendar, Ruler, Users, Settings,
  ChevronLeft, Thermometer, DoorOpen, Plus, Trash2,
} from 'lucide-react'
import type { Property, PropertyMember, Room, RoomType } from '@/lib/supabase/types'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { createClient } from '@/lib/supabase/client'
import { ROLE_LABELS } from '@/lib/supabase/types'

interface PropertyDetailProps {
  property: Property
  membership: PropertyMember
  members: PropertyMember[]
  rooms: Room[]
}

const ROOM_TYPE_LABELS: Record<RoomType, string> = {
  bedroom: 'Bedroom', bathroom: 'Bathroom', kitchen: 'Kitchen',
  living_room: 'Living Room', dining_room: 'Dining Room', office: 'Office',
  garage: 'Garage', basement: 'Basement', attic: 'Attic',
  hallway: 'Hallway', laundry: 'Laundry', storage: 'Storage',
  garden: 'Garden', balcony: 'Balcony', terrace: 'Terrace', other: 'Other',
}

export function PropertyDetail({ property, membership, members, rooms: initialRooms }: PropertyDetailProps) {
  const canEdit = membership.role === 'owner' || membership.role === 'partner'
  const [rooms, setRooms] = React.useState(initialRooms)
  const [addingRoom, setAddingRoom] = React.useState(false)
  const [newRoomName, setNewRoomName] = React.useState('')
  const [newRoomType, setNewRoomType] = React.useState<RoomType>('bedroom')
  const [savingRoom, setSavingRoom] = React.useState(false)

  async function handleAddRoom(e: React.FormEvent) {
    e.preventDefault()
    if (!newRoomName.trim()) return
    setSavingRoom(true)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data } = await (supabase as any)
      .from('rooms')
      .insert({ property_id: property.id, name: newRoomName.trim(), room_type: newRoomType, floor: 0, sort_order: rooms.length })
      .select('*')
      .single()
    if (data) setRooms((prev) => [...prev, data as Room])
    setNewRoomName('')
    setAddingRoom(false)
    setSavingRoom(false)
  }

  async function handleDeleteRoom(roomId: string) {
    if (!confirm('Remove this room?')) return
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('rooms').delete().eq('id', roomId)
    setRooms((prev) => prev.filter((r) => r.id !== roomId))
  }

  return (
    <div className="flex flex-col gap-0">
      {/* Header */}
      <header className="glass-opaque sticky top-0 z-20 border-b border-border/50 px-4 py-4 md:px-6">
        <div className="flex items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <Link
              href="/property"
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg glass-light text-muted-foreground hover:text-foreground transition-colors focus-ring"
            >
              <ChevronLeft className="h-4 w-4" />
            </Link>
            <div>
              <h1 className="text-lg font-bold text-foreground">{property.name}</h1>
              <p className="text-xs text-muted-foreground">{property.city}, {property.country}</p>
            </div>
          </div>
          {canEdit && (
            <Button asChild variant="ghost" size="icon">
              <Link href={`/property/${property.id}/edit`} aria-label="Edit property">
                <Settings className="h-4 w-4" />
              </Link>
            </Button>
          )}
        </div>
      </header>

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[88px] md:pb-6">
        {/* Hero */}
        <div className="glass-standard rounded-2xl p-5">
          <div className="flex items-start gap-4">
            <div
              className="flex h-14 w-14 shrink-0 items-center justify-center rounded-xl"
              style={{ background: 'hsl(36 78% 52% / 0.15)' }}
            >
              <Building2 className="h-7 w-7" style={{ color: 'hsl(36, 78%, 52%)' }} />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-xl font-bold text-foreground">{property.name}</p>
              <div className="mt-1 flex flex-wrap items-center gap-2">
                <Badge variant="neutral" size="sm">{property.property_type}</Badge>
                <Badge variant="neutral" size="sm">{ROLE_LABELS[membership.role]}</Badge>
              </div>
            </div>
            {property.health_score !== null && (
              <div className="text-right">
                <p className="text-2xl font-bold" style={{ color: getHealthColor(property.health_score) }}>
                  {property.health_score}
                </p>
                <p className="text-[10px] text-muted-foreground uppercase tracking-wider">Health</p>
              </div>
            )}
          </div>
        </div>

        {/* Address */}
        <Card variant="default" padding="md">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <MapPin className="h-4 w-4" />Address
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-foreground">{property.address_line1}</p>
            {property.address_line2 && <p className="text-sm text-foreground">{property.address_line2}</p>}
            <p className="text-sm text-foreground">
              {[property.city, property.state_province, property.postal_code].filter(Boolean).join(', ')}
            </p>
            <p className="text-sm text-muted-foreground">{property.country}</p>
          </CardContent>
        </Card>

        {/* Details grid */}
        <div className="grid grid-cols-2 gap-3">
          {property.size_sqm && (
            <DetailTile icon={<Ruler className="h-4 w-4" />} label="Size" value={`${property.size_sqm} m²`} />
          )}
          {property.year_built && (
            <DetailTile icon={<Calendar className="h-4 w-4" />} label="Built" value={String(property.year_built)} />
          )}
          {property.num_rooms && (
            <DetailTile icon={<Building2 className="h-4 w-4" />} label="Rooms" value={String(property.num_rooms)} />
          )}
          {property.heating_type && (
            <DetailTile icon={<Thermometer className="h-4 w-4" />} label="Heating" value={property.heating_type} />
          )}
        </div>

        {/* Rooms */}
        <Card variant="default" padding="md">
          <CardHeader>
            <div className="flex items-center justify-between">
              <CardTitle className="flex items-center gap-2">
                <DoorOpen className="h-4 w-4" />
                Rooms ({rooms.length})
              </CardTitle>
              {canEdit && !addingRoom && (
                <Button variant="ghost" size="icon-sm" onClick={() => setAddingRoom(true)} aria-label="Add room">
                  <Plus className="h-4 w-4" />
                </Button>
              )}
            </div>
          </CardHeader>
          <CardContent>
            <div className="flex flex-col gap-2">
              {rooms.length === 0 && !addingRoom && (
                <p className="text-sm text-muted-foreground py-1">
                  No rooms added yet.{canEdit ? ' Use + to add your first room.' : ''}
                </p>
              )}
              {rooms.map((room) => (
                <div key={room.id} className="flex items-center justify-between py-1">
                  <div className="flex items-center gap-2">
                    <div className="h-7 w-7 rounded-lg glass-standard flex items-center justify-center">
                      <DoorOpen className="h-3.5 w-3.5 text-muted-foreground" />
                    </div>
                    <div>
                      <p className="text-sm font-medium text-foreground">{room.name}</p>
                      <p className="text-xs text-muted-foreground">
                        {ROOM_TYPE_LABELS[room.room_type]}
                        {room.floor > 0 ? ` · Floor ${room.floor}` : ''}
                        {room.area_sqm ? ` · ${room.area_sqm} m²` : ''}
                      </p>
                    </div>
                  </div>
                  {canEdit && (
                    <Button
                      variant="ghost" size="icon-sm"
                      aria-label="Remove room"
                      onClick={() => handleDeleteRoom(room.id)}
                    >
                      <Trash2 className="h-3.5 w-3.5 text-destructive" />
                    </Button>
                  )}
                </div>
              ))}

              {/* Add room inline form */}
              {addingRoom && (
                <form onSubmit={handleAddRoom} className="flex flex-col gap-2 pt-2 border-t border-border/30">
                  <input
                    autoFocus
                    className="h-9 w-full rounded-lg border border-border bg-glass-light px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                    placeholder="Room name"
                    value={newRoomName}
                    onChange={(e) => setNewRoomName(e.target.value)}
                  />
                  <select
                    value={newRoomType}
                    onChange={(e) => setNewRoomType(e.target.value as RoomType)}
                    className="h-9 w-full rounded-lg border border-border bg-glass-light px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  >
                    {(Object.entries(ROOM_TYPE_LABELS) as [RoomType, string][]).map(([value, label]) => (
                      <option key={value} value={value}>{label}</option>
                    ))}
                  </select>
                  <div className="flex gap-2">
                    <Button type="button" variant="ghost" size="sm" className="flex-1" onClick={() => setAddingRoom(false)}>
                      Cancel
                    </Button>
                    <Button type="submit" variant="primary" size="sm" className="flex-1" loading={savingRoom}>
                      Add Room
                    </Button>
                  </div>
                </form>
              )}
            </div>
          </CardContent>
        </Card>

        {/* Members */}
        <Card variant="default" padding="md">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Users className="h-4 w-4" />
              Members ({members.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex flex-col gap-2">
              {members.map((member) => (
                <div key={member.id} className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <Avatar size="sm">
                      <AvatarFallback>{(member.nickname ?? 'M').charAt(0).toUpperCase()}</AvatarFallback>
                    </Avatar>
                    <span className="text-sm text-foreground">{member.nickname ?? 'Member'}</span>
                  </div>
                  <Badge variant="neutral" size="xs">{ROLE_LABELS[member.role]}</Badge>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

function DetailTile({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <Card variant="default" padding="sm">
      <div className="flex items-center gap-2 text-muted-foreground mb-1">
        {icon}
        <span className="text-xs">{label}</span>
      </div>
      <p className="text-sm font-semibold text-foreground capitalize">{value}</p>
    </Card>
  )
}

function getHealthColor(score: number): string {
  if (score >= 85) return 'hsl(152, 62%, 48%)'
  if (score >= 70) return 'hsl(45, 75%, 52%)'
  if (score >= 50) return 'hsl(22, 68%, 52%)'
  return 'hsl(0, 68%, 52%)'
}
