import type { Metadata } from 'next'
import { WifiOff, Clock, RefreshCw } from 'lucide-react'

export const metadata: Metadata = { title: 'Offline — PRV HOUSE' }

// Inline "P" mark — matches sidebar logo
function PRVLogoMark() {
  return (
    <svg
      width="32"
      height="32"
      viewBox="0 0 32 32"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
    >
      <rect width="32" height="32" rx="8" fill="url(#offlineLogoGrad)" />
      <text
        x="16"
        y="22"
        textAnchor="middle"
        fontFamily="system-ui, -apple-system, sans-serif"
        fontWeight="800"
        fontSize="18"
        fill="white"
      >
        P
      </text>
      <defs>
        <linearGradient id="offlineLogoGrad" x1="0" y1="0" x2="32" y2="32" gradientUnits="userSpaceOnUse">
          <stop stopColor="#6366f1" />
          <stop offset="1" stopColor="#8b5cf6" />
        </linearGradient>
      </defs>
    </svg>
  )
}

export default function OfflinePage() {
  return (
    <div
      className="flex min-h-dvh flex-col items-center justify-center px-6"
      style={{ background: '#0D1420' }}
    >
      <div className="w-full max-w-sm">
        {/* Glass card */}
        <div className="rounded-3xl border border-white/10 bg-white/5 backdrop-blur-xl p-8 text-center shadow-2xl">
          {/* Logo */}
          <div className="flex justify-center mb-6">
            <PRVLogoMark />
          </div>

          {/* Animated wifi-off icon */}
          <div className="relative flex h-20 w-20 items-center justify-center rounded-full border border-white/10 bg-white/5 mx-auto mb-6">
            {/* Pulse rings */}
            <span className="absolute inset-0 rounded-full border border-white/10 animate-ping opacity-30" />
            <span className="absolute inset-2 rounded-full border border-white/10 animate-ping opacity-20 [animation-delay:0.3s]" />
            <WifiOff className="h-9 w-9 text-white/50 relative z-10" />
          </div>

          <h1 className="text-2xl font-bold text-white mb-2">You&apos;re offline</h1>
          <p className="text-sm text-white/50 leading-relaxed mb-8">
            PRVIO requires a connection to sync your property data. Some cached pages may still be available.
          </p>

          {/* What you can still do */}
          <div className="text-left rounded-2xl border border-white/8 bg-white/[0.04] p-4 mb-6 space-y-3">
            <p className="text-xs font-semibold text-white/60 uppercase tracking-wider mb-3">What you can still do</p>
            <div className="flex items-start gap-3">
              <Clock className="h-4 w-4 text-white/40 mt-0.5 shrink-0" />
              <p className="text-sm text-white/70">View recently visited pages</p>
            </div>
            <div className="flex items-start gap-3">
              <RefreshCw className="h-4 w-4 text-white/40 mt-0.5 shrink-0" />
              <p className="text-sm text-white/70">The app will sync automatically when you reconnect</p>
            </div>
          </div>

          {/* Try again */}
          {/* eslint-disable-next-line @next/next/no-html-link-for-pages */}
          <a
            href="/"
            className="flex w-full items-center justify-center gap-2 rounded-xl bg-white/10 px-6 py-3 text-sm font-semibold text-white transition-colors hover:bg-white/20 active:scale-[0.98]"
          >
            <RefreshCw className="h-4 w-4" />
            Try again
          </a>
        </div>

        <p className="text-center text-xs text-white/20 mt-6">PRV HOUSE</p>
      </div>
    </div>
  )
}
