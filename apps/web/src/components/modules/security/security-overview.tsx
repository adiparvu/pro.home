'use client'

import * as React from 'react'
import { ShieldCheck, ShieldOff, Camera, Wifi, DoorOpen, Bell, Lock, Package } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import type { InventoryItem } from '@/lib/supabase/types'

type SecurityStatus = 'armed' | 'disarmed'
type SecurityItem = Pick<InventoryItem, 'id' | 'name' | 'brand' | 'category' | 'condition'>

interface SecurityOverviewProps {
  securityItems: SecurityItem[]
}

function guessDeviceIcon(name: string): React.ComponentType<{ className?: string }> {
  const n = name.toLowerCase()
  if (n.includes('camera')) return Camera
  if (n.includes('lock')) return Lock
  if (n.includes('door') || n.includes('window')) return DoorOpen
  if (n.includes('motion') || n.includes('alarm') || n.includes('sensor') || n.includes('detector')) return Bell
  return Package
}

export function SecurityOverview({ securityItems }: SecurityOverviewProps) {
  const [status, setStatus] = React.useState<SecurityStatus>('disarmed')
  const isArmed = status === 'armed'
  const hasRealDevices = securityItems.length > 0

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
            <p className={cn('mt-1 text-2xl font-bold', isArmed ? 'text-destructive' : 'text-foreground')}>
              {isArmed ? 'Armed' : 'Disarmed'}
            </p>
            <p className="text-sm text-muted-foreground mt-0.5">
              {hasRealDevices
                ? `${securityItems.length} device${securityItems.length !== 1 ? 's' : ''} in inventory`
                : 'No devices connected'}
            </p>
          </div>
          <button
            type="button"
            onClick={() => setStatus((s) => s === 'armed' ? 'disarmed' : 'armed')}
            className={cn(
              'flex h-16 w-16 flex-col items-center justify-center rounded-2xl transition-all duration-300 focus-ring',
              isArmed
                ? 'bg-destructive/20 hover:bg-destructive/30 text-destructive'
                : 'glass-standard hover:glass-heavy text-foreground'
            )}
          >
            {isArmed ? <ShieldOff className="h-7 w-7" /> : <ShieldCheck className="h-7 w-7" />}
            <span className="text-[9px] mt-0.5 font-medium">{isArmed ? 'Disarm' : 'Arm'}</span>
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
            {hasRealDevices && (
              <Badge variant="neutral" size="xs">{securityItems.length} in inventory</Badge>
            )}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {hasRealDevices ? (
            <div className="flex flex-col divide-y divide-border/30">
              {securityItems.map((item) => {
                const Icon = guessDeviceIcon(item.name)
                return (
                  <div key={item.id} className="flex items-center gap-3 py-3">
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
          ) : (
            <div className="flex flex-col items-center gap-2 py-6 text-center">
              <Package className="h-8 w-8 text-muted-foreground" />
              <p className="text-sm text-muted-foreground">
                No security devices in inventory.{' '}
                <a href="/inventory/new" className="underline hover:text-foreground">Add one</a>
                {' '}to track cameras, locks, and alarms here.
              </p>
            </div>
          )}
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
