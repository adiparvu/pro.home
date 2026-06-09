'use client'

import * as React from 'react'

function getTimeOfDayClass(): string {
  const hour = new Date().getHours()

  if (hour >= 5 && hour < 7) return 'dawn'
  if (hour >= 7 && hour < 10) return 'morning'
  if (hour >= 10 && hour < 14) return 'midday'
  if (hour >= 14 && hour < 18) return 'afternoon'
  if (hour >= 18 && hour < 20) return 'golden'
  if (hour >= 20 && hour < 21) return 'dusk'
  return 'night'
}

const TIME_GRADIENTS: Record<string, { from: string; via: string; to: string }> = {
  dawn: {
    from: 'hsl(22, 75%, 55%)',
    via: 'hsl(30, 60%, 70%)',
    to: 'hsl(210, 45%, 35%)',
  },
  morning: {
    from: 'hsl(195, 65%, 72%)',
    via: 'hsl(205, 55%, 82%)',
    to: 'hsl(210, 70%, 45%)',
  },
  midday: {
    from: 'hsl(200, 60%, 78%)',
    via: 'hsl(205, 65%, 85%)',
    to: 'hsl(215, 75%, 42%)',
  },
  afternoon: {
    from: 'hsl(195, 55%, 70%)',
    via: 'hsl(200, 50%, 78%)',
    to: 'hsl(210, 65%, 40%)',
  },
  golden: {
    from: 'hsl(32, 85%, 58%)',
    via: 'hsl(20, 70%, 60%)',
    to: 'hsl(260, 40%, 35%)',
  },
  dusk: {
    from: 'hsl(12, 65%, 48%)',
    via: 'hsl(280, 35%, 30%)',
    to: 'hsl(240, 35%, 15%)',
  },
  night: {
    from: 'hsl(235, 30%, 12%)',
    via: 'hsl(230, 28%, 8%)',
    to: 'hsl(225, 25%, 5%)',
  },
}

export function LpbeBackground() {
  const [tod, setTod] = React.useState(getTimeOfDayClass())

  React.useEffect(() => {
    // Update every 10 minutes
    const interval = setInterval(() => {
      setTod(getTimeOfDayClass())
    }, 10 * 60 * 1000)

    return () => clearInterval(interval)
  }, [])

  const gradient = TIME_GRADIENTS[tod] ?? TIME_GRADIENTS['night']!

  return (
    <div
      className="fixed inset-0 z-0 transition-all duration-[3000ms] ease-linear"
      aria-hidden="true"
      style={{
        background: `linear-gradient(to bottom, ${gradient.from} 0%, ${gradient.via} 40%, ${gradient.to} 100%)`,
      }}
    >
      {/* Subtle grain texture overlay */}
      <div
        className="absolute inset-0 opacity-[0.03]"
        style={{
          backgroundImage: 'url("data:image/svg+xml,%3Csvg viewBox=\'0 0 200 200\' xmlns=\'http://www.w3.org/2000/svg\'%3E%3Cfilter id=\'noise\'%3E%3CfeTurbulence type=\'fractalNoise\' baseFrequency=\'0.9\' numOctaves=\'4\' stitchTiles=\'stitch\'/%3E%3C/filter%3E%3Crect width=\'100%25\' height=\'100%25\' filter=\'url(%23noise)\' opacity=\'1\'/%3E%3C/svg%3E")',
          backgroundRepeat: 'repeat',
          backgroundSize: '200px 200px',
        }}
      />
      {/* Dark overlay for readability */}
      <div className="absolute inset-0 bg-black/30" />
    </div>
  )
}
