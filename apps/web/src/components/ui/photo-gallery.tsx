'use client'

import * as React from 'react'
import { Camera, X, Loader2, ZoomIn, ChevronLeft, ChevronRight } from 'lucide-react'

export interface PhotoGalleryProps {
  photos: string[]          // array of storage paths
  onAdd?: (path: string) => void
  onRemove?: (path: string) => void
  propertyId: string
  itemType: 'task' | 'defect'
  itemId: string
  readonly?: boolean
}

interface SignedEntry {
  path: string
  url: string | null
  loading: boolean
  error: boolean
}

export function PhotoGallery({
  photos,
  onAdd,
  onRemove,
  propertyId,
  itemType,
  itemId,
  readonly = false,
}: PhotoGalleryProps) {
  const [entries, setEntries] = React.useState<SignedEntry[]>([])
  const [uploading, setUploading] = React.useState(false)
  const [lightboxIndex, setLightboxIndex] = React.useState<number | null>(null)
  const fileInputRef = React.useRef<HTMLInputElement>(null)
  // Track which paths have already had a sign fetch initiated so we don't loop
  const fetchingRef = React.useRef<Set<string>>(new Set())

  // Sync entries when photos prop changes
  React.useEffect(() => {
    setEntries((prev) => {
      const existingMap = new Map(prev.map((e) => [e.path, e]))
      return photos.map((path) => {
        const existing = existingMap.get(path)
        if (existing) return existing
        return { path, url: null, loading: true, error: false }
      })
    })
  }, [photos])

  // Fetch signed URLs for any entries that need them
  React.useEffect(() => {
    const pending = entries.filter(
      (e) => e.loading && !e.url && !e.error && !fetchingRef.current.has(e.path)
    )
    if (pending.length === 0) return

    pending.forEach((entry) => {
      fetchingRef.current.add(entry.path)
      void (async () => {
        try {
          const res = await fetch(`/api/storage/sign?path=${encodeURIComponent(entry.path)}`)
          const json = await res.json() as { signedUrl?: string; error?: string }
          setEntries((prev) =>
            prev.map((e) =>
              e.path === entry.path
                ? { ...e, url: json.signedUrl ?? null, loading: false, error: !json.signedUrl }
                : e
            )
          )
        } catch {
          setEntries((prev) =>
            prev.map((e) =>
              e.path === entry.path ? { ...e, loading: false, error: true } : e
            )
          )
        }
      })()
    })
  }, [entries])

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    // Reset input so same file can be re-selected
    e.target.value = ''

    setUploading(true)
    try {
      const fd = new FormData()
      fd.append('file', file)
      fd.append('property_id', propertyId)
      fd.append('item_type', itemType)
      fd.append('item_id', itemId)

      const res = await fetch('/api/storage/upload', { method: 'POST', body: fd })
      const json = await res.json() as { path?: string; signedUrl?: string; error?: string }

      if (json.error || !json.path || !json.signedUrl) {
        console.error('Photo upload error:', json.error)
        return
      }

      // Add to entries immediately with the freshly obtained signed URL
      setEntries((prev) => [
        ...prev,
        { path: json.path!, url: json.signedUrl!, loading: false, error: false },
      ])
      onAdd?.(json.path!)
    } catch (err) {
      console.error('Photo upload failed:', err)
    } finally {
      setUploading(false)
    }
  }

  function handleRemove(path: string) {
    setEntries((prev) => prev.filter((e) => e.path !== path))
    onRemove?.(path)
  }

  const lightboxUrls = entries.map((e) => e.url).filter(Boolean) as string[]

  return (
    <>
      <div className="flex flex-wrap gap-2">
        {entries.map((entry, i) => (
          <div key={entry.path} className="relative group">
            {entry.loading && !entry.url ? (
              <div className="flex h-20 w-20 shrink-0 items-center justify-center rounded-xl border border-border bg-muted">
                <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
              </div>
            ) : entry.error ? (
              <div className="flex h-20 w-20 shrink-0 items-center justify-center rounded-xl border border-border bg-muted">
                <span className="text-[10px] text-muted-foreground text-center px-1">Failed to load</span>
              </div>
            ) : (
              <button
                type="button"
                onClick={() => setLightboxIndex(i)}
                className="block h-20 w-20 shrink-0 overflow-hidden rounded-xl border border-border focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50"
                aria-label={`View photo ${i + 1}`}
              >
                <img
                  src={entry.url!}
                  alt={`Photo ${i + 1}`}
                  className="h-full w-full object-cover transition-opacity group-hover:opacity-80"
                />
                <div className="absolute inset-0 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none">
                  <ZoomIn className="h-4 w-4 text-white drop-shadow-lg" />
                </div>
              </button>
            )}
            {!readonly && (
              <button
                type="button"
                onClick={() => handleRemove(entry.path)}
                className="absolute -top-1.5 -right-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-destructive text-white opacity-0 group-hover:opacity-100 transition-opacity shadow-md"
                aria-label="Remove photo"
              >
                <X className="h-3 w-3" />
              </button>
            )}
          </div>
        ))}

        {!readonly && (
          <label
            className={`flex h-20 w-20 shrink-0 cursor-pointer flex-col items-center justify-center gap-1 rounded-xl border border-dashed border-border transition-colors hover:bg-muted/50 ${
              uploading ? 'cursor-wait opacity-60' : ''
            }`}
            aria-label="Add photo"
          >
            {uploading ? (
              <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
            ) : (
              <>
                <Camera className="h-5 w-5 text-muted-foreground" />
                <span className="text-[10px] text-muted-foreground">Add photo</span>
              </>
            )}
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              className="sr-only"
              disabled={uploading}
              onChange={handleFileChange}
            />
          </label>
        )}
      </div>

      {/* Lightbox */}
      {lightboxIndex !== null && lightboxUrls.length > 0 && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/90 backdrop-blur-sm"
          onClick={() => setLightboxIndex(null)}
        >
          <button
            type="button"
            className="absolute top-4 right-4 flex h-9 w-9 items-center justify-center rounded-full bg-white/10 text-white hover:bg-white/20 transition-colors"
            onClick={() => setLightboxIndex(null)}
            aria-label="Close lightbox"
          >
            <X className="h-5 w-5" />
          </button>

          {lightboxUrls.length > 1 && (
            <>
              <button
                type="button"
                className="absolute left-4 top-1/2 -translate-y-1/2 flex h-9 w-9 items-center justify-center rounded-full bg-white/10 text-white hover:bg-white/20 transition-colors"
                onClick={(e) => {
                  e.stopPropagation()
                  setLightboxIndex((prev) =>
                    prev === null ? 0 : (prev - 1 + lightboxUrls.length) % lightboxUrls.length
                  )
                }}
                aria-label="Previous photo"
              >
                <ChevronLeft className="h-5 w-5" />
              </button>
              <button
                type="button"
                className="absolute right-4 top-1/2 -translate-y-1/2 flex h-9 w-9 items-center justify-center rounded-full bg-white/10 text-white hover:bg-white/20 transition-colors"
                onClick={(e) => {
                  e.stopPropagation()
                  setLightboxIndex((prev) =>
                    prev === null ? 0 : (prev + 1) % lightboxUrls.length
                  )
                }}
                aria-label="Next photo"
              >
                <ChevronRight className="h-5 w-5" />
              </button>
            </>
          )}

          <img
            src={lightboxUrls[lightboxIndex] ?? ''}
            alt={`Photo ${lightboxIndex + 1}`}
            className="max-h-[90vh] max-w-[90vw] rounded-xl object-contain"
            onClick={(e) => e.stopPropagation()}
          />

          {lightboxUrls.length > 1 && (
            <p className="absolute bottom-4 left-1/2 -translate-x-1/2 text-sm text-white/70">
              {lightboxIndex + 1} / {lightboxUrls.length}
            </p>
          )}
        </div>
      )}
    </>
  )
}

