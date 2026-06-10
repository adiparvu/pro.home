'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { FileText, ExternalLink, Trash2, Pencil, AlertCircle, X, Check } from 'lucide-react'
import type { Document, DocumentCategory } from '@/lib/supabase/types'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'

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
  if (!bytes) return '—'
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

export function DocumentDetail({ initialDoc }: { initialDoc: Document }) {
  const router = useRouter()
  const confirmDialog = useConfirm()
  const [doc, setDoc] = React.useState(initialDoc)
  const [editing, setEditing] = React.useState(false)
  const [deleting, setDeleting] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)

  const [editName, setEditName] = React.useState(doc.name)
  const [editDescription, setEditDescription] = React.useState(doc.description ?? '')
  const [editCategory, setEditCategory] = React.useState<DocumentCategory>(doc.category)
  const [editExpiresAt, setEditExpiresAt] = React.useState(doc.expires_at ? doc.expires_at.split('T')[0] : '')
  const [editCritical, setEditCritical] = React.useState(doc.is_critical)

  const color = CATEGORY_COLORS[doc.category]
  const expiresAt = doc.expires_at ? new Date(doc.expires_at) : null
  const isExpired = expiresAt ? expiresAt < new Date() : false
  const expiresSoon = expiresAt && !isExpired
    ? expiresAt < new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
    : false

  function cancelEdit() {
    setEditing(false)
    setEditName(doc.name)
    setEditDescription(doc.description ?? '')
    setEditCategory(doc.category)
    setEditExpiresAt(doc.expires_at ? doc.expires_at.split('T')[0] : '')
    setEditCritical(doc.is_critical)
    setError(null)
  }

  async function handleSave() {
    if (!editName.trim()) return
    setSaving(true)
    setError(null)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error: err } = await (supabase as any).from('documents').update({
      name: editName.trim(),
      description: editDescription.trim() || null,
      category: editCategory,
      expires_at: editExpiresAt || null,
      is_critical: editCritical,
    }).eq('id', doc.id)

    if (err) {
      setError((err as { message: string }).message)
      setSaving(false)
      return
    }

    setDoc((prev) => ({
      ...prev,
      name: editName.trim(),
      description: editDescription.trim() || null,
      category: editCategory,
      expires_at: editExpiresAt || null,
      is_critical: editCritical,
    }))
    setEditing(false)
    setSaving(false)
  }

  async function handleDelete() {
    const ok = await confirmDialog({
      title: `Delete "${doc.name}"?`,
      description: 'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeleting(true)
    const supabase = createClient()
    const storagePath = doc.file_url.split('/documents/').pop()
    if (storagePath) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any).storage.from('documents').remove([storagePath])
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('documents').delete().eq('id', doc.id)
    toast.success('Document deleted')
    router.push('/documents')
    router.refresh()
  }

  return (
    <>
      <PageHeader title="Document" backHref="/documents" />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6">
        {/* Hero card */}
        <Card variant="default" padding="lg">
          <div className="flex items-start gap-4">
            <div
              className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl"
              style={{ background: `${color}18`, border: `1px solid ${color}30` }}
            >
              <FileText className="h-7 w-7" style={{ color }} />
            </div>
            <div className="flex-1 min-w-0">
              {editing ? (
                <input
                  value={editName}
                  onChange={(e) => setEditName(e.target.value)}
                  className="w-full rounded-xl border border-border glass-light px-3 py-1.5 text-base font-semibold text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                  required
                />
              ) : (
                <p className="text-base font-semibold text-foreground leading-snug">{doc.name}</p>
              )}
              <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
                {editing ? (
                  <select
                    value={editCategory}
                    onChange={(e) => setEditCategory(e.target.value as DocumentCategory)}
                    className="rounded-xl border border-border glass-light px-2 py-0.5 text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 capitalize"
                  >
                    {CATEGORIES.map((c) => (
                      <option key={c} value={c} className="capitalize">{c}</option>
                    ))}
                  </select>
                ) : (
                  <Badge
                    variant="neutral"
                    size="xs"
                    className="capitalize"
                    style={{ color, borderColor: `${color}44`, background: `${color}18` }}
                  >
                    {doc.category}
                  </Badge>
                )}
                {!editing && doc.is_critical && <Badge variant="danger" size="xs">Critical</Badge>}
                {!editing && expiresAt && (
                  <Badge variant={isExpired ? 'critical' : expiresSoon ? 'warning' : 'neutral'} size="xs">
                    {isExpired
                      ? 'Expired'
                      : `Expires ${expiresAt.toLocaleDateString('en-US', { month: 'short', year: 'numeric' })}`}
                  </Badge>
                )}
              </div>
            </div>
          </div>
        </Card>

        {error && (
          <div className="flex items-center gap-2 rounded-xl border border-destructive/30 bg-destructive/10 px-3 py-2">
            <AlertCircle className="h-3.5 w-3.5 text-destructive shrink-0" />
            <p className="text-xs text-destructive">{error}</p>
          </div>
        )}

        {/* Details card */}
        <Card variant="default" padding="lg">
          <div className="flex flex-col gap-4">
            <div className="flex items-center justify-between">
              <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Details</p>
              {!editing ? (
                <Button variant="ghost" size="sm" onClick={() => setEditing(true)}>
                  <Pencil className="h-3.5 w-3.5" />
                  Edit
                </Button>
              ) : (
                <div className="flex gap-2">
                  <Button variant="ghost" size="sm" onClick={cancelEdit}>
                    <X className="h-3.5 w-3.5" />
                  </Button>
                  <Button variant="primary" size="sm" loading={saving} onClick={handleSave}>
                    <Check className="h-3.5 w-3.5" />
                    Save
                  </Button>
                </div>
              )}
            </div>

            <div className="flex flex-col gap-3">
              <DetailRow label="File name" value={doc.file_name} />
              <DetailRow label="Size" value={formatBytes(doc.file_size)} />
              {doc.mime_type && <DetailRow label="Type" value={doc.mime_type} />}
              <DetailRow
                label="Uploaded"
                value={new Date(doc.created_at).toLocaleDateString('en-US', {
                  month: 'long', day: 'numeric', year: 'numeric',
                })}
              />
              {editing ? (
                <>
                  <div className="flex flex-col gap-1.5 pt-1">
                    <label className="text-xs text-muted-foreground">Description</label>
                    <textarea
                      value={editDescription}
                      onChange={(e) => setEditDescription(e.target.value)}
                      rows={2}
                      placeholder="Optional"
                      className="w-full rounded-xl border border-border glass-light px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 resize-none"
                    />
                  </div>
                  <div className="flex flex-col gap-1.5">
                    <label className="text-xs text-muted-foreground">Expiry date</label>
                    <input
                      type="date"
                      value={editExpiresAt}
                      onChange={(e) => setEditExpiresAt(e.target.value)}
                      className="h-10 w-full rounded-xl border border-border glass-light px-3 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
                    />
                  </div>
                  <label className="flex items-center gap-3 cursor-pointer py-1">
                    <input
                      type="checkbox"
                      checked={editCritical}
                      onChange={(e) => setEditCritical(e.target.checked)}
                      className="h-4 w-4 rounded border-border accent-primary"
                    />
                    <span className="text-sm text-foreground">Mark as critical</span>
                  </label>
                </>
              ) : (
                <>
                  {doc.description && <DetailRow label="Description" value={doc.description} />}
                  {expiresAt && (
                    <DetailRow
                      label="Expiry"
                      value={expiresAt.toLocaleDateString('en-US', {
                        month: 'long', day: 'numeric', year: 'numeric',
                      })}
                    />
                  )}
                  <DetailRow label="Critical" value={doc.is_critical ? 'Yes' : 'No'} />
                </>
              )}
            </div>
          </div>
        </Card>

        {/* Actions */}
        <div className="flex flex-col gap-2">
          <a
            href={doc.file_url}
            target="_blank"
            rel="noopener noreferrer"
            className="flex h-11 w-full items-center justify-center gap-2 rounded-xl border border-border glass-light text-sm font-medium text-foreground hover:glass-standard transition-colors focus-ring"
          >
            <ExternalLink className="h-4 w-4" />
            Open document
          </a>
          <Button
            variant="destructive"
            size="lg"
            fullWidth
            loading={deleting}
            onClick={handleDelete}
          >
            <Trash2 className="h-4 w-4" />
            Delete document
          </Button>
        </div>
      </div>
    </>
  )
}

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-4">
      <p className="text-xs text-muted-foreground shrink-0">{label}</p>
      <p className="text-xs text-foreground text-right">{value}</p>
    </div>
  )
}
