'use client'

import * as React from 'react'
import Link from 'next/link'
import { Home, Wrench, FileText, Plus, Send, Loader2, ExternalLink, AlertTriangle, CheckCircle2 } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { toast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import type { Property } from '@/lib/supabase/types'

interface OpenTask {
  id: string
  title: string
  status: string
  priority: string
  due_date: string | null
  category: string | null
}

interface SharedDoc {
  id: string
  name: string
  category: string
  file_url: string
  expires_at: string | null
}

interface TenantPortalPageProps {
  property: Property
  userId: string
  memberRole: string
  openTasks: OpenTask[]
  sharedDocuments: SharedDoc[]
}

const PRIORITY_COLORS: Record<string, string> = {
  critical: 'hsl(0,68%,44%)',
  high: 'hsl(22,68%,45%)',
  medium: 'hsl(45,75%,42%)',
  low: 'hsl(0,0%,50%)',
}

export function TenantPortalPage({ property, userId, memberRole, openTasks, sharedDocuments }: TenantPortalPageProps) {
  const [requestTitle, setRequestTitle] = React.useState('')
  const [requestDesc, setRequestDesc] = React.useState('')
  const [submitting, setSubmitting] = React.useState(false)
  const [submitted, setSubmitted] = React.useState(false)
  const isTenant = memberRole === 'tenant' || memberRole === 'guest'

  async function submitRequest(e: React.FormEvent) {
    e.preventDefault()
    if (!requestTitle.trim()) return
    setSubmitting(true)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { error } = await (supabase as any)
        .from('maintenance_tasks')
        .insert({
          property_id: property.id,
          title: requestTitle.trim(),
          description: requestDesc.trim() || null,
          status: 'pending',
          priority: 'medium',
          category: 'maintenance',
          created_by: userId,
        })
      if (error) throw error
      setRequestTitle(''); setRequestDesc(''); setSubmitted(true)
      setTimeout(() => setSubmitted(false), 5000)
      toast({ title: 'Request submitted', description: 'The property manager has been notified.' })
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <>
      <PageHeader title="Tenant Portal" description={property.name} />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6">
        {/* Welcome card */}
        <Card className="p-4 flex items-center gap-4">
          <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-primary/10 text-primary shrink-0">
            <Home className="h-6 w-6" />
          </div>
          <div>
            <p className="font-semibold text-sm">{property.name}</p>
            <p className="text-xs text-muted-foreground capitalize">Role: {memberRole.replace(/_/g, ' ')}</p>
            {(property as unknown as { address?: string | null }).address && <p className="text-xs text-muted-foreground mt-0.5">{(property as unknown as { address?: string }).address}</p>}
          </div>
        </Card>

        {/* Submit maintenance request */}
        <Card className="p-4">
          <div className="flex items-center gap-2 mb-3">
            <Wrench className="h-4 w-4 text-muted-foreground" />
            <p className="text-sm font-semibold">Submit a Request</p>
          </div>
          {submitted ? (
            <div className="flex items-center gap-2 rounded-xl bg-green-500/10 border border-green-500/20 p-3">
              <CheckCircle2 className="h-4 w-4 text-green-500" />
              <p className="text-sm text-green-500">Request submitted! The property manager will be in touch.</p>
            </div>
          ) : (
            <form onSubmit={submitRequest} className="space-y-3">
              <Input
                placeholder="What needs attention? *"
                value={requestTitle}
                onChange={(e) => setRequestTitle(e.target.value)}
                required
              />
              <textarea
                placeholder="Describe the issue (optional)"
                value={requestDesc}
                onChange={(e) => setRequestDesc(e.target.value)}
                rows={3}
                className="w-full rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <Button type="submit" size="sm" disabled={submitting || !requestTitle.trim()}>
                {submitting ? <Loader2 className="h-3.5 w-3.5 animate-spin mr-1" /> : <Send className="h-3.5 w-3.5 mr-1" />}
                Submit request
              </Button>
            </form>
          )}
        </Card>

        {/* Open maintenance tasks (read-only) */}
        {openTasks.length > 0 && (
          <Card className="p-0 overflow-hidden">
            <div className="px-4 py-3 border-b border-border/30 flex items-center gap-2">
              <Wrench className="h-4 w-4 text-muted-foreground" />
              <p className="text-sm font-semibold">Open Maintenance ({openTasks.length})</p>
            </div>
            <div className="divide-y divide-border/30">
              {openTasks.map((task) => (
                <div key={task.id} className="flex items-center gap-3 px-4 py-3">
                  <div
                    className="h-2 w-2 rounded-full shrink-0"
                    style={{ background: PRIORITY_COLORS[task.priority] ?? 'hsl(0,0%,50%)' }}
                  />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm truncate">{task.title}</p>
                    {task.due_date && (
                      <p className="text-xs text-muted-foreground">Due: {task.due_date}</p>
                    )}
                  </div>
                  <Badge variant="neutral" className="text-[10px] capitalize shrink-0">
                    {task.status.replace('_', ' ')}
                  </Badge>
                </div>
              ))}
            </div>
          </Card>
        )}

        {/* Shared documents (leases, insurance, etc.) */}
        {sharedDocuments.length > 0 && (
          <Card className="p-0 overflow-hidden">
            <div className="px-4 py-3 border-b border-border/30 flex items-center gap-2">
              <FileText className="h-4 w-4 text-muted-foreground" />
              <p className="text-sm font-semibold">Important Documents</p>
            </div>
            <div className="divide-y divide-border/30">
              {sharedDocuments.map((doc) => (
                <div key={doc.id} className="flex items-center gap-3 px-4 py-3">
                  <FileText className="h-4 w-4 text-muted-foreground shrink-0" />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm truncate">{doc.name}</p>
                    <p className="text-xs text-muted-foreground capitalize">{doc.category}</p>
                  </div>
                  <a
                    href={doc.file_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex h-7 w-7 items-center justify-center rounded-lg glass-light text-muted-foreground hover:text-foreground transition-colors shrink-0"
                  >
                    <ExternalLink className="h-3.5 w-3.5" />
                  </a>
                </div>
              ))}
            </div>
          </Card>
        )}

        {/* Emergency info */}
        <Card className="p-4 border-destructive/20">
          <div className="flex items-center gap-2 mb-2">
            <AlertTriangle className="h-4 w-4 text-destructive" />
            <p className="text-sm font-semibold text-destructive">Emergency</p>
          </div>
          <p className="text-xs text-muted-foreground">
            For urgent issues (burst pipes, gas leaks, fire) call emergency services immediately (112 / 911)
            and contact your property manager right away.
          </p>
          <Link href="/marketplace?tab=emergency" className="mt-2 inline-flex items-center gap-1 text-xs text-primary hover:underline">
            View emergency contacts →
          </Link>
        </Card>
      </div>
    </>
  )
}
