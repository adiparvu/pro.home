'use client'

import * as React from 'react'
import { useTheme } from 'next-themes'
import { Sun, Moon, Monitor } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { cn } from '@/lib/utils'

const THEMES = [
  { id: 'light', label: 'Light', icon: Sun },
  { id: 'dark', label: 'Dark', icon: Moon },
  { id: 'system', label: 'System', icon: Monitor },
]

export function AppearanceSettings() {
  const { theme, setTheme } = useTheme()

  return (
    <div className="flex flex-col gap-6 max-w-lg">
      <Card variant="default" padding="lg">
        <CardHeader>
          <CardTitle>Theme</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-3 gap-3">
            {THEMES.map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                type="button"
                onClick={() => setTheme(id)}
                className={cn(
                  'flex flex-col items-center gap-2 rounded-xl p-4 transition-all duration-fast focus-ring',
                  theme === id
                    ? 'glass-standard ring-2 ring-primary/60'
                    : 'glass-light hover:glass-standard'
                )}
              >
                <Icon className={cn(
                  'h-5 w-5 transition-colors',
                  theme === id ? 'text-primary' : 'text-muted-foreground'
                )} />
                <span className={cn(
                  'text-xs font-medium',
                  theme === id ? 'text-foreground' : 'text-muted-foreground'
                )}>
                  {label}
                </span>
              </button>
            ))}
          </div>
        </CardContent>
      </Card>

      <Card variant="default" padding="lg">
        <CardHeader>
          <CardTitle>Motion</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            Motion preferences are respected from your system settings.
            Reduce motion in your OS accessibility settings to disable animations.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
