'use client'

import * as React from 'react'
import Link from 'next/link'
import { FileText, Upload, AlertCircle, Trash2, ExternalLink, ChevronDown, ChevronUp } from 'lucide-react'
import type { Property, Document, DocumentCategory } from '@/lib/supabase/types'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'

interface DocumentsPageProps {
  property: Property
  userId: string
  initialDocuments: Document[]
}

const CATEGORIES: DocumentCategory[] = ['legal', 'insurance', 'warranty', 'manual', 'invoice', 'permit', 'tax', 'utility', 'other']

const CATEGORY_COLORS: Record<DocumentCategory, string> = {
  legal:     'hsl(220,62%,52%)',
  insurance: 'hsl(152,62%,42%)',
  warranty:  'hsl(270,62%,52%)',
  manual:    'hsl(45,75%,42%)',
  invoice:   'hsl(22,68%,45%)',
  permit:    'hsl(180,52%,42%)',
  tax:       'hsl(0,68%,44%)',
  utility:   'hsl(220,30%,52%)',
  other:     'hsl(0,0%,50%)',
}

function formatBytes(bytes: number | null) {
  if (!bytes) return ''
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

export function DocumentsPage({ property, userId, initialDocuments }: DocumentsPageProps) {
  const confirmDialog = useConfirm()
  const [documents, setDocuments] = React.useState<Document[]>(initialDocuments)
  const [categoryFilter, setCategoryFilter] = React.useState<DocumentCategory | null>(null)
  const [showUpload, setShowUpload] = React.useState(false)
  const [uploading, setUploading] = React.useState(false)
  const [uploadError, setUploadError] = React.useState<string | null>(null)
  const [deletingId, setDeletingId] = React.useState<string | null>(null)

  const [uploadName, setUploadName] = React.useState('')
  const [uploadCategory, setUploadCategory] = React.useState<DocumentCategory>('other')
  const [uploadDescription, setUploadDescription] = React.useState('')
  const [uploadExpiresAt, setUploadExpiresAt] = React.useState('')
  const [uploadFile, setUploadFile] = React.useState<File | null>(null)
  const fileInputRef = React.useRef<HTMLInputElement>(null)

  const filtered = categoryFilter ? documents.filter((d) => d.category === categoryFilter) : documents
  const criticalCount = documents.filter((d) => d.is_critical).length

  async function handleUpload(e: React.FormEvent) {
    e.preventDefault()
    if (!uploadFile || !uploadName.trim()) return
    setUploading(true)
    setUploadError(null)

    try {
      const supabase = createClient()
      const ext = uploadFile.name.split('.').pop()
      const path = `${property.id}/${Date.now()}-${uploadFile.name.replace(/[^a-z0-9.-]/gi, '_')}`

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { error: storageError } = await (supabase as any).storage
        .from('documents')
        .upload(path, uploadFile, { contentType: uploadFile.type })

      if (storageError) throw new Error((storageError as { message: string }).message)

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: urlData } = (supabase as any).storage.from('documents').getPublicUrl(path)
      const fileUrl = urlData?.publicUrl ?? ''

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data: doc, error: dbError } = await (supabase as any)
        .from('documents')
        .insert({
          property_id: property.id,
          name: uploadName.trim(),
          description: uploadDescription.trim() || null,
          category: uploadCategory,
          file_url: fileUrl,
          file_name: uploadFile.name,
          file_size: uploadFile.size,
          mime_type: uploadFile.type,
          tags: [],
          expires_at: uploadExpiresAt || null,
          is_critical: false,
          uploaded_by: userId,
        })
        .select()
        .single()

      if (dbError) throw new Error((dbError as { message: string }).message)

      setDocuments((prev) => [doc as Document, ...prev])
      setShowUpload(false)
      setUploadName('')
      setUploadDescription('')
      setUploadCategory('other')
      setUploadExpiresAt('')
      setUploadFile(null)
    } catch (err) {
      setUploadError(err instanceof Error ? err.message : 'Upload failed')
    } finally {
      setUploading(false)
    }
  }

  async function handleDelete(doc: Document) {
    const ok = await confirmDialog({
      title: `Delete "${doc.name}"?`,
      description: 'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeletingId(doc.id)
    const supabase = createClient()

    const storagePath = doc.file_url.split('/documents/').pop()
    if (storagePath) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).storage.from('documents').remove([storagePath])
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('documents').delete().eq('id', doc.id)
    toast.success('Document deleted')
    setDocuments((prev) => prev.filter((d) => d.id !== doc.id))
    setDeletingId(null)
  }

  return (
    <>
      <PageHeader
        title="Documents"
        description={property.name}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Stats */}
        <div className="grid grid-cols-3 gap-3">
          <StatTile label="Total" value={String(documents.length)} />
          <StatTile label="Critical" value={String(criticalCount)} alert={criticalCount > 0} />
          <StatTile
            label="Expiring"
            value={String(documents.filter((d) => {
              if (!d.expires_at) return false
              const exp = new Date(d.expires_at)
              const soon = new Date()
              soon.setDate(soon.getDate() + 30)
              return exp < soon && exp > new Date()
            }).length)}
          />
        </div>

        {/* Upload toggle */}
        <Button
          variant="secondary"
          size="sm"
          onClick={() => setShowUpload((v) => !v)}
          className="self-start"
        >
          <Upload className="h-3.5 w-3.5" />
          {showUpload ? 'Cancel upload' : 'Upload document'}
          {showUpload ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
        </Button>

        {/* Upload form */}
        {showUpload && (
          <Card variant="default" padding="md">
            <form onSubmit={handleUpload} className="flex flex-col gap-4">
              {uploadError && (
                <div className="flex items-center gap-2 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2">
                  <AlertCircle className="h-3.5 w-3.5 text-destructive shrink-0" />
                  <p className="text-xs text-destructive">{uploadError}</p>
                </div>
              )}

              <div className="flex flex-col gap-2">
                <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Document name *</label>
                <input
                  value={uploadName}
                  onChange={(e) => setUploadName(e.target.value)}
                  placeholder='e.g. "Home Insurance Policy 2024"'
                  className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  required
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="flex flex-col gap-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Category</label>
                  <select
                    value={uploadCategory}
                    onChange={(e) => setUploadCategory(e.target.value as DocumentCategory)}
                    className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 capitalize"
                  >
                    {CATEGORIES.map((c) => (
                      <option key={c} value={c} className="capitalize">{c}</option>
                    ))}
                  </select>
                </div>
                <div className="flex flex-col gap-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">File *</label>
                  <div className="relative">
                    <input
                      ref={fileInputRef}
                      type="file"
                      accept=".pdf,.doc,.docx,.jpg,.jpeg,.png,.webp"
                      onChange={(e) => setUploadFile(e.target.files?.[0] ?? null)}
                      className="hidden"
                    />
                    <button
                      type="button"
                      onClick={() => fileInputRef.current?.click()}
                      className="h-10 w-full rounded-xl border border-border glass-light px-3 text-left text-sm focus:outline-none focus:ring-2 focus:ring-primary/60 truncate"
                    >
                      <span className={uploadFile ? 'text-foreground' : 'text-muted-foreground'}>
                        {uploadFile ? uploadFile.name : 'Choose file…'}
                      </span>
                    </button>
                  </div>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="flex flex-col gap-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Description</label>
                  <input
                    value={uploadDescription}
                    onChange={(e) => setUploadDescription(e.target.value)}
                    placeholder="Optional"
                    className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  />
                </div>
                <div className="flex flex-col gap-2">
                  <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Expiry date</label>
                  <input
                    type="date"
                    value={uploadExpiresAt}
                    onChange={(e) => setUploadExpiresAt(e.target.value)}
                    className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  />
                </div>
              </div>

              <Button type="submit" size="sm" loading={uploading} disabled={!uploadFile || !uploadName.trim()}>
                <Upload className="h-3.5 w-3.5" />
                Upload
              </Button>
            </form>
          </Card>
        )}

        {/* Category filter */}
        {documents.length > 0 && (
          <div className="flex gap-2 overflow-x-auto scrollbar-hide">
            <button
              type="button"
              onClick={() => setCategoryFilter(null)}
              className={`shrink-0 rounded-full px-3 py-1 text-xs font-medium transition-colors ${
                !categoryFilter ? 'bg-primary text-white' : 'glass-light text-muted-foreground hover:text-foreground'
              }`}
            >
              All
            </button>
            {CATEGORIES.filter((c) => documents.some((d) => d.category === c)).map((cat) => (
              <button
                key={cat}
                type="button"
                onClick={() => setCategoryFilter(categoryFilter === cat ? null : cat)}
                className={`shrink-0 rounded-full px-3 py-1 text-xs font-medium capitalize transition-colors ${
                  categoryFilter === cat ? 'bg-primary text-white' : 'glass-light text-muted-foreground hover:text-foreground'
                }`}
              >
                {cat}
              </button>
            ))}
          </div>
        )}

        {/* Document list */}
        {filtered.length === 0 ? (
          <EmptyState hasDocuments={documents.length > 0} />
        ) : (
          <div className="flex flex-col gap-2">
            {filtered.map((doc) => (
              <DocumentCard
                key={doc.id}
                doc={doc}
                onDelete={handleDelete}
                deleting={deletingId === doc.id}
              />
            ))}
          </div>
        )}
      </div>
    </>
  )
}

function DocumentCard({
  doc,
  onDelete,
  deleting,
}: {
  doc: Document
  onDelete: (doc: Document) => void
  deleting: boolean
}) {
  const expiresAt = doc.expires_at ? new Date(doc.expires_at) : null
  const isExpired = expiresAt ? expiresAt < new Date() : false
  const expiresSoon = expiresAt && !isExpired ? expiresAt < new Date(Date.now() + 30 * 24 * 60 * 60 * 1000) : false
  const color = CATEGORY_COLORS[doc.category]

  return (
    <Card variant="default" padding="md">
      <div className="flex items-start gap-3">
        <div
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl"
          style={{ background: `${color}18`, border: `1px solid ${color}30` }}
        >
          <FileText className="h-5 w-5" style={{ color }} />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <Link href={`/documents/${doc.id}`} className="text-sm font-medium text-foreground truncate hover:text-primary transition-colors">{doc.name}</Link>
              {doc.description && (
                <p className="text-xs text-muted-foreground mt-0.5 line-clamp-1">{doc.description}</p>
              )}
            </div>
            <div className="flex shrink-0 items-center gap-1.5">
              <a
                href={doc.file_url}
                target="_blank"
                rel="noopener noreferrer"
                className="flex h-7 w-7 items-center justify-center rounded-lg glass-light text-muted-foreground hover:text-foreground transition-colors"
                aria-label="Open document"
              >
                <ExternalLink className="h-3.5 w-3.5" />
              </a>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => onDelete(doc)}
                loading={deleting}
                aria-label="Delete document"
                className="h-7 w-7"
              >
                <Trash2 className="h-3.5 w-3.5 text-destructive" />
              </Button>
            </div>
          </div>
          <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
            <Badge variant="neutral" size="xs" className="capitalize" style={{ color, borderColor: `${color}44`, background: `${color}18` }}>
              {doc.category}
            </Badge>
            {doc.file_size && (
              <span className="text-[10px] text-muted-foreground">{formatBytes(doc.file_size)}</span>
            )}
            {expiresAt && (
              <Badge variant={isExpired ? 'critical' : expiresSoon ? 'warning' : 'neutral'} size="xs">
                {isExpired ? 'Expired' : `Expires ${expiresAt.toLocaleDateString('en-US', { month: 'short', year: 'numeric' })}`}
              </Badge>
            )}
            {doc.is_critical && <Badge variant="danger" size="xs">Critical</Badge>}
          </div>
        </div>
      </div>
    </Card>
  )
}

function StatTile({ label, value, alert }: { label: string; value: string; alert?: boolean }) {
  return (
    <Card variant="default" padding="sm">
      <p className={`text-xl font-bold ${alert ? 'text-destructive' : 'text-foreground'}`}>{value}</p>
      <p className="text-xs text-muted-foreground mt-0.5">{label}</p>
    </Card>
  )
}

function EmptyState({ hasDocuments }: { hasDocuments: boolean }) {
  return (
    <div className="flex flex-col items-center gap-3 py-16 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-2xl glass-standard">
        <FileText className="h-7 w-7 text-muted-foreground" />
      </div>
      <p className="font-semibold text-foreground">
        {hasDocuments ? 'No documents match' : 'No documents yet'}
      </p>
      <p className="text-sm text-muted-foreground max-w-[200px]">
        {hasDocuments
          ? 'Try a different category filter'
          : 'Upload insurance policies, warranties, invoices, and more'}
      </p>
    </div>
  )
}
