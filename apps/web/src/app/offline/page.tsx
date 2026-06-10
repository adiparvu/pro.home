import type { Metadata } from 'next'
import { WifiOff } from 'lucide-react'

export const metadata: Metadata = { title: 'Offline — PRV HOUSE' }

export default function OfflinePage() {
  return (
    <div
      className="flex min-h-dvh flex-col items-center justify-center gap-6 px-6 text-center"
      style={{ background: '#0D1420' }}
    >
      <div className="flex h-20 w-20 items-center justify-center rounded-3xl border border-white/10 bg-white/5 backdrop-blur-md">
        <WifiOff className="h-10 w-10 text-white/50" />
      </div>
      <div className="flex flex-col gap-2">
        <h1 className="text-2xl font-bold text-white">You&apos;re offline</h1>
        <p className="max-w-[260px] text-sm text-white/50">
          PRV HOUSE needs a connection to load your property data. Check your network and try again.
        </p>
      </div>
      {/* eslint-disable-next-line @next/next/no-html-link-for-pages */}
      <a
        href="/"
        className="rounded-xl bg-white/10 px-6 py-3 text-sm font-semibold text-white transition-colors hover:bg-white/20"
      >
        Try again
      </a>
    </div>
  )
}
