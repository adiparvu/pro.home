import type { Metadata, Viewport } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'

const inter = Inter({
  subsets: ['latin'],
  variable: '--font-sans',
  display: 'swap',
})

export const metadata: Metadata = {
  title: {
    template: '%s | PRV HOUSE',
    default: 'PRV HOUSE — The Property Operating System',
  },
  description:
    'The most intelligent property management platform. Monitor, maintain, and master your home with AI-powered insights.',
  keywords: ['property management', 'smart home', 'property OS', 'home maintenance', 'ARIA AI'],
  authors: [{ name: 'PRV HOUSE' }],
  creator: 'PRV HOUSE',
  metadataBase: new URL(process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'),
  openGraph: {
    type: 'website',
    title: 'PRV HOUSE — The Property Operating System',
    description: 'The most intelligent property management platform.',
    siteName: 'PRV HOUSE',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'PRV HOUSE',
    description: 'The most intelligent property management platform.',
  },
  manifest: '/manifest.json',
  appleWebApp: {
    capable: true,
    statusBarStyle: 'black-translucent',
    title: 'PRV HOUSE',
  },
}

export const viewport: Viewport = {
  themeColor: [
    { media: '(prefers-color-scheme: dark)', color: '#0D1420' },
    { media: '(prefers-color-scheme: light)', color: '#F7F8FA' },
  ],
  width: 'device-width',
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  viewportFit: 'cover',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head />
      <body className={`${inter.variable} min-h-dvh`}>{children}</body>
    </html>
  )
}
