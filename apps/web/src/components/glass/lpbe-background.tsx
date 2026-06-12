'use client'

import * as React from 'react'
import { useTheme } from 'next-themes'

export function LpbeBackground() {
  const { resolvedTheme } = useTheme()
  const [mounted, setMounted] = React.useState(false)

  React.useEffect(() => { setMounted(true) }, [])

  const isDark = !mounted || resolvedTheme !== 'light'

  const gradient = isDark
    ? 'linear-gradient(to bottom, hsl(0,0%,10%) 0%, hsl(0,0%,7%) 40%, hsl(0,0%,4%) 100%)'
    : 'linear-gradient(to bottom, hsl(0,0%,95%) 0%, hsl(0,0%,91%) 40%, hsl(0,0%,84%) 100%)'

  return (
    <div
      className="fixed inset-0 z-0 transition-all duration-[800ms] ease-linear"
      aria-hidden="true"
      style={{ background: gradient }}
    >
      {/* Subtle grain texture overlay */}
      <div
        className="absolute inset-0 opacity-[0.025]"
        style={{
          backgroundImage: 'url("data:image/svg+xml,%3Csvg viewBox=\'0 0 200 200\' xmlns=\'http://www.w3.org/2000/svg\'%3E%3Cfilter id=\'noise\'%3E%3CfeTurbulence type=\'fractalNoise\' baseFrequency=\'0.9\' numOctaves=\'4\' stitchTiles=\'stitch\'/%3E%3C/filter%3E%3Crect width=\'100%25\' height=\'100%25\' filter=\'url(%23noise)\' opacity=\'1\'/%3E%3C/svg%3E")',
          backgroundRepeat: 'repeat',
          backgroundSize: '200px 200px',
        }}
      />
    </div>
  )
}
