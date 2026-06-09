'use client'

import * as React from 'react'
import { ShieldCheck, ShieldOff, Camera, Wifi, DoorOpen, Bell, Lock } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'

type SecurityStatus = 'armed' | 'disarmed' | 'alert'

interface SecurityDevice {
  id: string
  name: string
  type: 'camera' | 'door' | 'window' | 'motion' | 'lock'
  status: 'online' | 'offline' | 'triggered'
  location: string
}

const MOCK_DEVICES: SecurityDevice[] = [
  { id: '1', name: 'Front Door Camera', type: 'camera', status: 'online', location: 'Entrance' },
  { id: '2', name: 'Back Garden Camera', type: 'camera', status: 'online', location: 'Garden' },
  { id: '3', name: 'Front Door Lock', type: 'lock', status: 'online', location: 'Entrance' },
  { id: '4', name: 'Back Door', type: 'door', status: 'online', location: 'Kitchen' },
]

const DEVICE_ICONS: Record<SecurityDevice['type'], React.ComponentType<{ className?: string }>> = {
  camera: Camera,
  door: DoorOpen,
  window: DoorOpen,
  motion: Bell,
  lock: Lock,
}

export function SecurityOverview() {
  const [status, setStatus] = React.useState<SecurityStatus>('disarmed')
  const isArmed = status === 'armed'
  const onlineCount = MOCK_DEVICES.filter((d) => d.status === 'online').length

  function toggleArm() {
    setStatus((prev) => (prev === 'armed' ? 'disarmed' : 'armed'))
  }

  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
      {/* Status hero */}
      <div
        className={cn(
          'rounded-2xl p-5 transition-colors duration-500',
          isArmed ? 'bg-destructive/10 border border-destructive/20' : 'glass-standard'
        )}
      >
        <div className="flex items-center justify-between">
          <div>
            <p className="text-xs text-muted-foreground uppercase tracking-wider">Status</p>
            <p className={cn(
              'mt-1 text-2xl font-bold',
              isArmed ? 'text-destructive' : 'text-foreground'
            )}>
              {isArmed ? 'Armed' : 'Disarmed'}
            </p>
            <p className="text-sm text-muted-foreground mt-0.5">
              {onlineCount}/{MOCK_DEVICES.length} devices online
            </p>
          </div>
          <button
            type="button"
            onClick={toggleArm}
            className={cn(
              'flex h-16 w-16 flex-col items-center justify-center rounded-2xl transition-all duration-300 focus-ring',
              isArmed
                ? 'bg-destructive/20 hover:bg-destructive/30 text-destructive'
                : 'glass-standard hover:glass-heavy text-foreground'
            )}
          >
            {isArmed ? (
              <ShieldOff className="h-7 w-7" />
            ) : (
              <ShieldCheck className="h-7 w-7" />
            )}
            <span className="text-[9px] mt-0.5 font-medium">
              {isArmed ? 'Disarm' : 'Arm'}
            </span>
          </button>
        </div>
      </div>

      {/* Device list */}
      <Card variant="default" padding="md">
        <CardHeader>
          <CardTitle className="flex items-center justify-between">
            <span className="flex items-center gap-2">
              <Wifi className="h-4 w-4" />
              Devices
            </span>
            <Badge variant="success" size="xs">{onlineCount} online</Badge>
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col divide-y divide-border/30">
            {MOCK_DEVICES.map((device) => {
              const Icon = DEVICE_ICONS[device.type]
              return (
                <div key={device.id} className="flex items-center gap-3 py-3">
                  <div className="flex h-9 w-9 items-center justify-center rounded-xl glass-light shrink-0">
                    <Icon className="h-4 w-4 text-muted-foreground" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-foreground truncate">{device.name}</p>
                    <p className="text-xs text-muted-foreground">{device.location}</p>
                  </div>
                  <Badge
                    variant={device.status === 'online' ? 'success' : device.status === 'triggered' ? 'danger' : 'neutral'}
                    size="xs"
                    dot
                  >
                    {device.status}
                  </Badge>
                </div>
              )
            })}
          </div>
        </CardContent>
      </Card>

      {/* Integration notice */}
      <div className="rounded-xl border border-border/50 glass-light p-4 text-center">
        <p className="text-sm font-medium text-foreground">Connect Security System</p>
        <p className="mt-1 text-xs text-muted-foreground">
          Integrate with Ring, Nest, Hikvision, or any Z-Wave system in Phase 4
        </p>
        <button
          type="button"
          disabled
          className="mt-3 rounded-full glass-standard px-4 py-1.5 text-xs text-muted-foreground cursor-not-allowed"
        >
          Add Integration (Phase 4)
        </button>
      </div>
    </div>
  )
}
