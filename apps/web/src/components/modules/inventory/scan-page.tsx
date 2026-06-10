'use client'

import * as React from 'react'
import Link from 'next/link'
import { Camera, Search, Package, Plus, ArrowLeft, AlertCircle } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import type { InventoryItem } from '@/lib/supabase/types'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'

interface ScanPageProps {
  propertyId: string | null
}

export function ScanPage({ propertyId }: ScanPageProps) {
  const [manualCode, setManualCode] = React.useState('')
  const [searching, setSearching] = React.useState(false)
  const [results, setResults] = React.useState<InventoryItem[] | null>(null)
  const [error, setError] = React.useState<string | null>(null)
  const [lastCode, setLastCode] = React.useState('')
  const fileInputRef = React.useRef<HTMLInputElement>(null)

  async function lookupCode(code: string) {
    if (!propertyId || !code.trim()) return
    setSearching(true)
    setError(null)
    setResults(null)
    setLastCode(code.trim())

    const supabase = createClient()
    const trimmed = code.trim()

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data, error: dbError } = await (supabase as any)
      .from('inventory_items')
      .select('*')
      .eq('property_id', propertyId)
      .or(`barcode.eq.${trimmed},serial_number.eq.${trimmed}`)
      .limit(10) as { data: InventoryItem[] | null; error: unknown }

    if (dbError) {
      setError('Lookup failed. Please try again.')
    } else {
      setResults(data ?? [])
    }
    setSearching(false)
  }

  async function handleFileCapture(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return

    if ('BarcodeDetector' in window) {
      try {
        const bitmap = await createImageBitmap(file)
        // @ts-expect-error BarcodeDetector not in TS lib
        const detector = new BarcodeDetector({
          formats: ['ean_13', 'ean_8', 'qr_code', 'code_128', 'code_39', 'upc_a', 'upc_e'],
        })
        const codes: { rawValue: string }[] = await detector.detect(bitmap)
        if (codes.length > 0 && codes[0]) {
          const code = codes[0].rawValue
          setManualCode(code)
          await lookupCode(code)
          return
        }
        setError('No barcode detected in the image. Enter the code manually below.')
      } catch {
        setError('Barcode detection failed. Enter the code manually below.')
      }
    } else {
      setError('Automatic barcode detection is not supported on this browser. Enter the code manually below.')
    }

    // Reset file input so the same file can be re-selected
    if (fileInputRef.current) fileInputRef.current.value = ''
  }

  function handleManualSubmit(e: React.FormEvent) {
    e.preventDefault()
    lookupCode(manualCode)
  }

  return (
    <>
      <PageHeader title="M-SCAN™" description="Scan or enter a barcode or serial number" />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Camera capture */}
        <Card variant="default" padding="md">
          <div className="flex flex-col items-center gap-4 py-2">
            <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-primary/10">
              <Camera className="h-8 w-8 text-primary" />
            </div>
            <div className="text-center">
              <p className="text-sm font-semibold text-foreground">Scan Barcode</p>
              <p className="text-xs text-muted-foreground mt-0.5">
                Point your camera at a product barcode or QR code
              </p>
            </div>
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              capture="environment"
              onChange={handleFileCapture}
              className="hidden"
            />
            <Button variant="primary" size="sm" onClick={() => fileInputRef.current?.click()}>
              <Camera className="h-3.5 w-3.5" />
              Open Camera
            </Button>
          </div>
        </Card>

        {/* Manual entry */}
        <Card variant="default" padding="md">
          <form onSubmit={handleManualSubmit} className="flex flex-col gap-3">
            <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              Manual Entry
            </p>
            <div className="flex gap-2">
              <input
                value={manualCode}
                onChange={(e) => setManualCode(e.target.value)}
                placeholder="Barcode or serial number"
                className="flex-1 h-10 rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
              />
              <Button
                type="submit"
                variant="secondary"
                size="sm"
                loading={searching}
                disabled={!manualCode.trim()}
                className="shrink-0"
              >
                <Search className="h-3.5 w-3.5" />
                Search
              </Button>
            </div>
          </form>
        </Card>

        {/* Error */}
        {error && (
          <div className="flex items-center gap-2 rounded-xl border border-destructive/30 bg-destructive/10 px-4 py-3">
            <AlertCircle className="h-4 w-4 text-destructive shrink-0" />
            <p className="text-sm text-destructive">{error}</p>
          </div>
        )}

        {/* Results */}
        {results !== null && (
          <div className="flex flex-col gap-3">
            <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              {results.length > 0
                ? `${results.length} item${results.length !== 1 ? 's' : ''} found`
                : 'No items found'}
            </p>

            {results.length === 0 ? (
              <Card variant="default" padding="md">
                <div className="flex flex-col items-center gap-3 py-4 text-center">
                  <Package className="h-8 w-8 text-muted-foreground" />
                  <div>
                    <p className="text-sm font-medium text-foreground">Not in inventory</p>
                    <p className="text-xs text-muted-foreground mt-0.5">
                      No items match &ldquo;{lastCode}&rdquo;
                    </p>
                  </div>
                  <Link href="/inventory/new">
                    <Button variant="secondary" size="sm">
                      <Plus className="h-3.5 w-3.5" />
                      Add to Inventory
                    </Button>
                  </Link>
                </div>
              </Card>
            ) : (
              results.map((item) => (
                <Link key={item.id} href={`/inventory/${item.id}`}>
                  <Card variant="default" hover padding="md">
                    <div className="flex items-center gap-3">
                      <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary/10">
                        <Package className="h-5 w-5 text-primary" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-foreground truncate">{item.name}</p>
                        <p className="text-xs text-muted-foreground">
                          {[item.brand, item.model].filter(Boolean).join(' · ')}
                        </p>
                      </div>
                      {item.condition && (
                        <Badge variant="neutral" size="xs" className="capitalize shrink-0">
                          {item.condition}
                        </Badge>
                      )}
                    </div>
                  </Card>
                </Link>
              ))
            )}
          </div>
        )}

        <Link
          href="/inventory"
          className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground transition-colors self-start mt-2"
        >
          <ArrowLeft className="h-3.5 w-3.5" />
          Back to Inventory
        </Link>
      </div>
    </>
  )
}
