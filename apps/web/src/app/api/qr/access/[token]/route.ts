import { NextRequest, NextResponse } from 'next/server'
import { qrWithLogo } from '@/lib/qr-with-logo'

interface Props { params: Promise<{ token: string }> }

export async function GET(req: NextRequest, { params }: Props) {
  const { token } = await params

  const appUrl = process.env.NEXT_PUBLIC_APP_URL ?? 'https://app.prvhouse.com'
  const accessUrl = `${appUrl}/access/${token}`

  const svg = await qrWithLogo(accessUrl, {
    width: 200,
    margin: 2,
    dark: '#1a1a2e',
    light: '#ffffff',
  })

  return new NextResponse(svg, {
    headers: { 'Content-Type': 'image/svg+xml', 'Cache-Control': 'no-store' },
  })
}
