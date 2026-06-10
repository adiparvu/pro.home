'use client'

import * as React from 'react'
import {
  ShieldCheck, ShieldOff, Home, Moon, Plane,
  Camera, Lock, DoorOpen, Bell, Package,
  AlertTriangle, CheckCircle2, Wifi, WifiOff, Battery,
  AlertCircle, Plus, X, ChevronDown, ChevronUp, Clock, Trash2, ToggleLeft, ToggleRight,
} from 'lucide-react'
import type { SecurityState, SecurityMode, SecurityEvent, SecurityEventType, SecuritySeverity, InventoryItem, SecuritySchedule } from '@/lib/supabase/types'
import { createClient } from '@/lib/supabase/client'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'

type SecurityItem = Pick<InventoryItem, 'id' | 'name' | 'brand' | 'category' | 'condition'>

interface SecurityOverviewProps {
  propertyId: string
  securityState: SecurityState | null
  events: SecurityEvent[]
  securityItems: SecurityItem[]
  schedules: SecuritySchedule[]
}

const MODE_CONFIG: Record<SecurityMode, {
  label: string
  shortLabel: string
  icon: React.ComponentType<{ className?: string; style?: React.CSSProperties }>
  color: string
  bg: string
  isArmed: boolean
}> = {
  disarmed: { label: 'Disarmed',    shortLabel: 'Off',     icon: ShieldOff,   color: 'hsl(152,62%,48%)', bg: 'hsl(152,62%,48%,0.12)', isArmed: false },
  home:     { label: 'Armed Home',  shortLabel: 'Home',    icon: Home,        color: 'hsl(210,70%,52%)', bg: 'hsl(210,70%,52%,0.12)', isArmed: true  },
  away:     { label: 'Armed Away',  shortLabel: 'Away',    icon: ShieldCheck, color: 'hsl(22,68%,52%)',  bg: 'hsl(22,68%,52%,0.12)',  isArmed: true  },
  night:    { label: 'Night Mode',  shortLabel: 'Night',   icon: Moon,        color: 'hsl(260,60%,56%)', bg: 'hsl(260,60%,56%,0.12)', isArmed: true  },
  vacation: { label: 'Vacation',    shortLabel: 'Vacation',icon: Plane,       color: 'hsl(0,68%,52%)',   bg: 'hsl(0,68%,52%,0.12)',   isArmed: true  },
}

const SEVERITY_COLORS: Record<SecuritySeverity, string> = {
  info:     'hsl(210,70%,52%)',
  warning:  'hsl(45,75%,48%)',
  alert:    'hsl(22,68%,52%)',
  critical: 'hsl(0,68%,52%)',
}

const EVENT_TYPE_LABELS: Record<SecurityEventType, string> = {
  armed:            'Armed',
  disarmed:         'Disarmed',
  motion_detected:  'Motion detected',
  door_opened:      'Door opened',
  window_opened:    'Window opened',
  alarm_triggered:  'Alarm triggered',
  alarm_cleared:    'Alarm cleared',
  battery_low:      'Battery low',
  offline:          'Device offline',
  online:           'Device online',
  test:             'Test event',
  manual:           'Manual entry',
}

const DAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const ALL_DAYS = [1, 2, 3, 4, 5, 6, 0] // Mon-Sun (Sun=0 matches JS Date)

function getEventIcon(type: SecurityEventType): React.ComponentType<{ className?: string; style?: React.CSSProperties }> {
  switch (type) {
    case 'armed': return ShieldCheck
    case 'disarmed': return ShieldOff
    case 'motion_detected': return AlertTriangle
    case 'door_opened': case 'window_opened': return DoorOpen
    case 'alarm_triggered': return Bell
    case 'alarm_cleared': return CheckCircle2
    case 'battery_low': return Battery
    case 'offline': return WifiOff
    case 'online': return Wifi
    default: return AlertCircle
  }
}

function guessDeviceIcon(name: string): React.ComponentType<{ className?: string }> {
  const n = name.toLowerCase()
  if (n.includes('camera')) return Camera
  if (n.includes('lock')) return Lock
  if (n.includes('door') || n.includes('window')) return DoorOpen
  if (n.includes('motion') || n.includes('alarm') || n.includes('sensor') || n.includes('detector')) return Bell
  return Package
}

function formatScheduleDays(days: number[]): string {
  const sorted = [...days].sort((a, b) => (a === 0 ? 7 : a) - (b === 0 ? 7 : b))
  if (sorted.length === 7) return 'Every day'
  if (sorted.length === 5 && !sorted.includes(0) && !sorted.includes(6)) return 'Weekdays'
  if (sorted.length === 2 && sorted.includes(0) && sorted.includes(6)) return 'Weekends'
  return sorted.map((d) => DAY_LABELS[d]).join(', ')
}

const LOG_EVENT_TYPES: SecurityEventType[] = [
  'motion_detected', 'door_opened', 'window_opened',
  'alarm_triggered', 'alarm_cleared', 'battery_low',
  'offline', 'online', 'test', 'manual',
]

export function SecurityOverview({ propertyId, securityState, events: initialEvents, securityItems, schedules: initialSchedules }: SecurityOverviewProps) {
  const [currentMode, setCurrentMode] = React.useState<SecurityMode>(securityState?.mode ?? 'disarmed')
  const [events, setEvents] = React.useState<SecurityEvent[]>(initialEvents)
  const [updating, setUpdating] = React.useState(false)
  const [showLogForm, setShowLogForm] = React.useState(false)
  const [logType, setLogType] = React.useState<SecurityEventType>('manual')
  const [logSeverity, setLogSeverity] = React.useState<SecuritySeverity>('info')
  const [logDesc, setLogDesc] = React.useState('')
  const [logging, setLogging] = React.useState(false)
  const [showAllEvents, setShowAllEvents] = React.useState(false)

  // Schedule state
  const [schedules, setSchedules] = React.useState<SecuritySchedule[]>(initialSchedules)
  const [showScheduleForm, setShowScheduleForm] = React.useState(false)
  const [schedLabel, setSchedLabel] = React.useState('')
  const [schedMode, setSchedMode] = React.useState<SecurityMode>('disarmed')
  const [schedDays, setSchedDays] = React.useState<number[]>([1, 2, 3, 4, 5, 6, 0])
  const [schedTime, setSchedTime] = React.useState('22:00')
  const [savingSched, setSavingSched] = React.useState(false)

  const config = MODE_CONFIG[currentMode]
  const StatusIcon = config.icon
  const isArmed = config.isArmed

  async function refreshEvents() {
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data } = await (supabase as any).from('security_events').select('*').eq('property_id', propertyId).order('created_at', { ascending: false }).limit(50) as { data: SecurityEvent[] | null }
    if (data) setEvents(data)
  }

  async function setMode(newMode: SecurityMode) {
    if (newMode === currentMode || updating) return
    setUpdating(true)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).rpc('set_security_mode', { p_property_id: propertyId, p_mode: newMode })
    setCurrentMode(newMode)
    await refreshEvents()
    setUpdating(false)
  }

  async function logEvent() {
    setLogging(true)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('security_events').insert({
      property_id: propertyId,
      event_type: logType,
      severity: logSeverity,
      description: logDesc || null,
      device_id: null,
      created_by: null,
    })
    setLogDesc('')
    setLogType('manual')
    setLogSeverity('info')
    setShowLogForm(false)
    await refreshEvents()
    setLogging(false)
  }

  async function resolveEvent(id: string) {
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('security_events').update({ resolved_at: new Date().toISOString() }).eq('id', id)
    setEvents((prev) => prev.map((e) => e.id === id ? { ...e, resolved_at: new Date().toISOString() } : e))
  }

  async function saveSchedule(e: React.FormEvent) {
    e.preventDefault()
    if (!schedTime || schedDays.length === 0) return
    setSavingSched(true)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data } = await (supabase as any).from('security_schedules').insert({
      property_id: propertyId,
      label: schedLabel || null,
      mode: schedMode,
      days_of_week: schedDays,
      time_hhmm: schedTime,
      enabled: true,
    }).select().single() as { data: SecuritySchedule | null }
    if (data) setSchedules((prev) => [...prev, data].sort((a, b) => a.time_hhmm.localeCompare(b.time_hhmm)))
    setSchedLabel('')
    setSchedMode('disarmed')
    setSchedDays([1, 2, 3, 4, 5, 6, 0])
    setSchedTime('22:00')
    setShowScheduleForm(false)
    setSavingSched(false)
  }

  async function toggleSchedule(sched: SecuritySchedule) {
    const supabase = createClient()
    const newEnabled = !sched.enabled
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('security_schedules').update({ enabled: newEnabled }).eq('id', sched.id)
    setSchedules((prev) => prev.map((s) => s.id === sched.id ? { ...s, enabled: newEnabled } : s))
  }

  async function deleteSchedule(id: string) {
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('security_schedules').delete().eq('id', id)
    setSchedules((prev) => prev.filter((s) => s.id !== id))
  }

  function toggleDay(day: number) {
    setSchedDays((prev) =>
      prev.includes(day) ? prev.filter((d) => d !== day) : [...prev, day]
    )
  }

  const visibleEvents = showAllEvents ? events : events.slice(0, 5)
  const unresolvedCritical = events.filter((e) => !e.resolved_at && (e.severity === 'critical' || e.severity === 'alert')).length

  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[88px] md:pb-6">
      {/* Status hero */}
      <div
        className="rounded-2xl p-5 transition-colors duration-300"
        style={{
          background: isArmed ? `${config.color}14` : undefined,
          border: isArmed ? `1px solid ${config.color}30` : undefined,
        }}
      >
        <div className="flex items-center justify-between mb-4">
          <div>
            <p className="text-xs text-muted-foreground uppercase tracking-wider">Security</p>
            <p className="mt-1 text-2xl font-bold" style={{ color: config.color }}>
              {config.label}
            </p>
            <p className="text-xs text-muted-foreground mt-0.5">
              {securityState?.armed_at
                ? `Since ${new Date(securityState.armed_at).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })}`
                : isArmed ? 'System armed' : 'System disarmed'
              }
            </p>
          </div>
          <div
            className="flex h-14 w-14 flex-col items-center justify-center rounded-2xl"
            style={{ background: config.bg }}
          >
            <StatusIcon className="h-7 w-7" style={{ color: config.color }} />
          </div>
        </div>

        {/* Mode buttons */}
        <div className="grid grid-cols-5 gap-1.5">
          {(Object.keys(MODE_CONFIG) as SecurityMode[]).map((mode) => {
            const { shortLabel, icon: Icon, color } = MODE_CONFIG[mode]
            const active = mode === currentMode
            return (
              <button
                key={mode}
                type="button"
                onClick={() => setMode(mode)}
                disabled={updating}
                className={cn(
                  'flex flex-col items-center gap-1 rounded-xl px-2 py-2 text-[10px] font-medium transition-all focus-ring disabled:opacity-60',
                  active
                    ? ''
                    : 'glass-light text-muted-foreground hover:text-foreground'
                )}
                style={active ? { background: `${color}18`, color, boxShadow: `0 0 0 1px ${color}50` } : undefined}
              >
                <Icon className="h-4 w-4" />
                {shortLabel}
              </button>
            )
          })}
        </div>
      </div>

      {/* Unresolved critical alerts */}
      {unresolvedCritical > 0 && (
        <div className="flex items-center gap-3 rounded-xl border border-destructive/30 bg-destructive/10 px-4 py-3">
          <AlertTriangle className="h-4 w-4 text-destructive shrink-0" />
          <p className="text-sm text-destructive font-medium flex-1">
            {unresolvedCritical} unresolved alert{unresolvedCritical !== 1 ? 's' : ''}
          </p>
        </div>
      )}

      {/* Schedules */}
      <div className="flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Auto Schedules</p>
          <button
            type="button"
            onClick={() => setShowScheduleForm((v) => !v)}
            className="flex items-center gap-1 text-xs font-medium text-primary hover:text-primary/80 transition-colors"
          >
            <Plus className="h-3.5 w-3.5" />
            Add schedule
          </button>
        </div>

        {/* Add schedule form */}
        {showScheduleForm && (
          <Card variant="default" padding="md">
            <form onSubmit={saveSchedule} className="flex flex-col gap-3">
              <div className="flex items-center justify-between">
                <p className="text-xs font-semibold text-foreground">New schedule</p>
                <button type="button" onClick={() => setShowScheduleForm(false)} className="text-muted-foreground hover:text-foreground">
                  <X className="h-4 w-4" />
                </button>
              </div>

              {/* Label */}
              <input
                value={schedLabel}
                onChange={(e) => setSchedLabel(e.target.value)}
                placeholder="Label (optional, e.g. Bedtime)"
                className="h-9 rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
              />

              {/* Mode + Time */}
              <div className="grid grid-cols-2 gap-2">
                <div className="flex flex-col gap-1">
                  <label className="text-xs text-muted-foreground">Switch to</label>
                  <select
                    value={schedMode}
                    onChange={(e) => setSchedMode(e.target.value as SecurityMode)}
                    className="h-9 rounded-xl border border-border bg-glass-light px-2 text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  >
                    {(Object.keys(MODE_CONFIG) as SecurityMode[]).map((m) => (
                      <option key={m} value={m}>{MODE_CONFIG[m].label}</option>
                    ))}
                  </select>
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-xs text-muted-foreground">At time</label>
                  <input
                    type="time"
                    value={schedTime}
                    onChange={(e) => setSchedTime(e.target.value)}
                    required
                    className="h-9 rounded-xl border border-border glass-light px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  />
                </div>
              </div>

              {/* Days of week */}
              <div className="flex flex-col gap-1.5">
                <label className="text-xs text-muted-foreground">Days</label>
                <div className="flex gap-1 flex-wrap">
                  {ALL_DAYS.map((day) => (
                    <button
                      key={day}
                      type="button"
                      onClick={() => toggleDay(day)}
                      className={cn(
                        'h-8 w-10 rounded-lg text-xs font-medium transition-colors',
                        schedDays.includes(day)
                          ? 'bg-primary/20 text-primary ring-1 ring-primary/50'
                          : 'glass-light text-muted-foreground hover:text-foreground'
                      )}
                    >
                      {DAY_LABELS[day]}
                    </button>
                  ))}
                </div>
              </div>

              <Button
                variant="primary"
                size="sm"
                type="submit"
                loading={savingSched}
                disabled={schedDays.length === 0}
                className="self-end"
              >
                Save schedule
              </Button>
            </form>
          </Card>
        )}

        {schedules.length === 0 && !showScheduleForm ? (
          <div className="flex flex-col items-center gap-2 py-6 text-center rounded-2xl border border-border/50 glass-light">
            <Clock className="h-7 w-7 text-muted-foreground" />
            <p className="text-xs text-muted-foreground">No schedules yet — add one to automate arm/disarm</p>
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            {schedules.map((sched) => {
              const modeConf = MODE_CONFIG[sched.mode]
              const ModeIcon = modeConf.icon
              return (
                <Card key={sched.id} variant="default" padding="sm" className={cn(!sched.enabled && 'opacity-50')}>
                  <div className="flex items-center gap-3 px-1">
                    <div
                      className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl"
                      style={{ background: `${modeConf.color}18` }}
                    >
                      <ModeIcon className="h-4 w-4" style={{ color: modeConf.color }} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-1.5">
                        <p className="text-sm font-medium text-foreground">
                          {sched.time_hhmm}
                        </p>
                        <span className="text-xs text-muted-foreground">→</span>
                        <p className="text-sm text-foreground">{modeConf.label}</p>
                      </div>
                      <p className="text-[11px] text-muted-foreground mt-0.5">
                        {sched.label ? `${sched.label} · ` : ''}{formatScheduleDays(sched.days_of_week)}
                      </p>
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      <button
                        type="button"
                        onClick={() => toggleSchedule(sched)}
                        className="text-muted-foreground hover:text-foreground transition-colors p-1"
                        aria-label={sched.enabled ? 'Disable schedule' : 'Enable schedule'}
                      >
                        {sched.enabled
                          ? <ToggleRight className="h-5 w-5 text-primary" />
                          : <ToggleLeft className="h-5 w-5" />
                        }
                      </button>
                      <button
                        type="button"
                        onClick={() => deleteSchedule(sched.id)}
                        className="text-muted-foreground hover:text-destructive transition-colors p-1"
                        aria-label="Delete schedule"
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </div>
                  </div>
                </Card>
              )
            })}
          </div>
        )}
      </div>

      {/* Events */}
      <div className="flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Recent Events</p>
          <button
            type="button"
            onClick={() => setShowLogForm((v) => !v)}
            className="flex items-center gap-1 text-xs font-medium text-primary hover:text-primary/80 transition-colors"
          >
            <Plus className="h-3.5 w-3.5" />
            Log event
          </button>
        </div>

        {/* Log event inline form */}
        {showLogForm && (
          <Card variant="default" padding="md">
            <div className="flex flex-col gap-3">
              <div className="flex items-center justify-between">
                <p className="text-xs font-semibold text-foreground">Log a security event</p>
                <button type="button" onClick={() => setShowLogForm(false)} className="text-muted-foreground hover:text-foreground">
                  <X className="h-4 w-4" />
                </button>
              </div>
              <div className="grid grid-cols-2 gap-2">
                <div className="flex flex-col gap-1">
                  <label className="text-xs text-muted-foreground">Event type</label>
                  <select
                    value={logType}
                    onChange={(e) => setLogType(e.target.value as SecurityEventType)}
                    className="h-9 rounded-xl border border-border bg-glass-light px-2 text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  >
                    {LOG_EVENT_TYPES.map((t) => (
                      <option key={t} value={t}>{EVENT_TYPE_LABELS[t]}</option>
                    ))}
                  </select>
                </div>
                <div className="flex flex-col gap-1">
                  <label className="text-xs text-muted-foreground">Severity</label>
                  <select
                    value={logSeverity}
                    onChange={(e) => setLogSeverity(e.target.value as SecuritySeverity)}
                    className="h-9 rounded-xl border border-border bg-glass-light px-2 text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 capitalize"
                  >
                    {(['info', 'warning', 'alert', 'critical'] as SecuritySeverity[]).map((s) => (
                      <option key={s} value={s} className="capitalize">{s}</option>
                    ))}
                  </select>
                </div>
              </div>
              <input
                value={logDesc}
                onChange={(e) => setLogDesc(e.target.value)}
                placeholder="Description (optional)"
                className="h-9 rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
              />
              <Button variant="primary" size="sm" loading={logging} onClick={logEvent} className="self-end">
                Save event
              </Button>
            </div>
          </Card>
        )}

        {events.length === 0 ? (
          <div className="flex flex-col items-center gap-2 py-8 text-center rounded-2xl border border-border/50 glass-light">
            <ShieldCheck className="h-8 w-8 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">No security events logged yet</p>
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            {visibleEvents.map((event) => {
              const EventIcon = getEventIcon(event.event_type)
              const severity = event.severity
              const color = SEVERITY_COLORS[severity]
              const isResolved = !!event.resolved_at
              const date = new Date(event.created_at)
              return (
                <Card key={event.id} variant="default" padding="md" className={cn(isResolved && 'opacity-60')}>
                  <div className="flex items-start gap-3">
                    <div
                      className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl"
                      style={{ background: `${color}18` }}
                    >
                      <EventIcon className="h-4 w-4" style={{ color }} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <p className={cn('text-sm font-medium', isResolved ? 'line-through text-muted-foreground' : 'text-foreground')}>
                          {EVENT_TYPE_LABELS[event.event_type]}
                        </p>
                        <Badge variant="neutral" size="xs" className="capitalize shrink-0" style={{ color, borderColor: `${color}44`, background: `${color}14` }}>
                          {severity}
                        </Badge>
                        {isResolved && <Badge variant="neutral" size="xs">Resolved</Badge>}
                      </div>
                      {event.description && (
                        <p className="text-xs text-muted-foreground mt-0.5">{event.description}</p>
                      )}
                      <p className="text-[10px] text-muted-foreground mt-1">
                        {date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
                        {' · '}
                        {date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })}
                      </p>
                    </div>
                    {!isResolved && (severity === 'critical' || severity === 'alert' || severity === 'warning') && (
                      <button
                        type="button"
                        onClick={() => resolveEvent(event.id)}
                        className="shrink-0 text-xs text-muted-foreground hover:text-foreground transition-colors"
                      >
                        Resolve
                      </button>
                    )}
                  </div>
                </Card>
              )
            })}
            {events.length > 5 && (
              <button
                type="button"
                onClick={() => setShowAllEvents((v) => !v)}
                className="flex items-center justify-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors py-1"
              >
                {showAllEvents ? <ChevronUp className="h-3 w-3" /> : <ChevronDown className="h-3 w-3" />}
                {showAllEvents ? 'Show less' : `Show ${events.length - 5} more`}
              </button>
            )}
          </div>
        )}
      </div>

      {/* Security devices from inventory */}
      <div className="flex flex-col gap-3">
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Devices in Inventory</p>
        {securityItems.length > 0 ? (
          <Card variant="default" padding="md">
            <div className="flex flex-col divide-y divide-border/30">
              {securityItems.map((item) => {
                const Icon = guessDeviceIcon(item.name)
                return (
                  <div key={item.id} className="flex items-center gap-3 py-3 first:pt-0 last:pb-0">
                    <div className="flex h-9 w-9 items-center justify-center rounded-xl glass-light shrink-0">
                      <Icon className="h-4 w-4 text-muted-foreground" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-foreground truncate">{item.name}</p>
                      <p className="text-xs text-muted-foreground">{item.brand ?? item.category ?? 'Security device'}</p>
                    </div>
                    <Badge
                      variant={item.condition === 'broken' ? 'danger' : item.condition === 'poor' ? 'warning' : 'neutral'}
                      size="xs"
                      className="capitalize shrink-0"
                    >
                      {item.condition ?? 'Unknown'}
                    </Badge>
                  </div>
                )
              })}
            </div>
          </Card>
        ) : (
          <div className="flex flex-col items-center gap-2 py-6 text-center rounded-2xl border border-border/50 glass-light">
            <Package className="h-7 w-7 text-muted-foreground" />
            <p className="text-xs text-muted-foreground">
              No security devices in inventory.{' '}
              <a href="/inventory/new" className="underline hover:text-foreground">Add one</a>
              {' '}to track cameras, locks, and alarms here.
            </p>
          </div>
        )}
      </div>
    </div>
  )
}
