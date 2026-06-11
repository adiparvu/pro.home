'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import {
  Wrench, Calendar, DollarSign, Clock, User, CheckSquare,
  Square, ChevronLeft, Pencil, Trash2, CheckCircle2, AlertTriangle,
  Phone, Mail, MapPin, Package, Tag, XCircle, Image, Camera, Loader2, Plus,
  MessageSquare, Send,
} from 'lucide-react'
import Link from 'next/link'
import type { MaintenanceTask, TaskStatus, TaskPriority } from '@/lib/supabase/types'
import { createClient } from '@/lib/supabase/client'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import { formatRelativeTime } from '@/lib/utils'

interface ContractorMessage {
  id: string
  task_id: string
  sender_id: string
  content: string
  is_read: boolean
  created_at: string
}

interface TaskDetailProps {
  task: MaintenanceTask
  assigneeName?: string | null
  roomName?: string | null
  inventoryItemName?: string | null
  userId?: string | null
}

const PRIORITY_VARIANTS: Record<TaskPriority, 'critical' | 'danger' | 'warning' | 'neutral'> = {
  critical: 'critical', high: 'danger', medium: 'warning', low: 'neutral',
}
const STATUS_COLORS: Record<TaskStatus, string> = {
  pending:     'hsl(45,75%,42%)',
  in_progress: 'hsl(220,62%,52%)',
  completed:   'hsl(152,62%,42%)',
  cancelled:   'hsl(0,0%,50%)',
  overdue:     'hsl(0,68%,44%)',
}

type ChecklistItem = { text: string; done: boolean }

export function TaskDetail({ task: initial, assigneeName, roomName, inventoryItemName, userId }: TaskDetailProps) {
  const router = useRouter()
  const confirmDialog = useConfirm()
  const [task, setTask] = React.useState(initial)
  const [checklist, setChecklist] = React.useState<ChecklistItem[]>(() => {
    try {
      const raw = initial.checklist
      if (Array.isArray(raw)) return raw as ChecklistItem[]
    } catch { /* ignore */ }
    return []
  })
  const [deleting, setDeleting] = React.useState(false)
  const [updatingStatus, setUpdatingStatus] = React.useState(false)
  const [uploadingSlot, setUploadingSlot] = React.useState<'before' | 'after' | null>(null)
  const [messages, setMessages] = React.useState<ContractorMessage[]>([])
  const [msgText, setMsgText] = React.useState('')
  const [sendingMsg, setSendingMsg] = React.useState(false)
  const [loadingMsgs, setLoadingMsgs] = React.useState(false)
  const chatEndRef = React.useRef<HTMLDivElement>(null)

  React.useEffect(() => {
    async function loadMessages() {
      setLoadingMsgs(true)
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data } = await (supabase as any)
        .from('contractor_messages')
        .select('*')
        .eq('task_id', initial.id)
        .order('created_at', { ascending: true })
        .limit(100)
      if (data) setMessages(data as ContractorMessage[])
      setLoadingMsgs(false)
    }
    void loadMessages()
  }, [initial.id])

  React.useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  async function sendMessage(e: React.FormEvent) {
    e.preventDefault()
    if (!msgText.trim() || !userId) return
    setSendingMsg(true)
    try {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any)
        .from('contractor_messages')
        .insert({ task_id: task.id, sender_id: userId, content: msgText.trim() })
        .select()
        .single()
      if (error) { toast.error('Failed to send'); return }
      setMessages((prev) => [...prev, data as ContractorMessage])
      setMsgText('')
    } finally {
      setSendingMsg(false)
    }
  }

  async function handlePhotoUpload(file: File, slot: 'before' | 'after') {
    setUploadingSlot(slot)
    try {
      const fd = new FormData()
      fd.append('file', file)
      fd.append('taskId', task.id)
      fd.append('slot', slot)
      const res = await fetch('/api/storage/task-photos', { method: 'POST', body: fd })
      const json = await res.json() as { url?: string; error?: string }
      if (json.error) { toast.error(json.error); return }
      if (json.url) {
        const field = slot === 'after' ? 'after_photo_urls' : 'before_photo_urls'
        setTask((prev) => ({ ...prev, [field]: [...(prev[field] ?? []), json.url!] }))
        toast.success('Photo added')
        router.refresh()
      }
    } finally {
      setUploadingSlot(null)
    }
  }

  async function updateStatus(status: TaskStatus) {
    setUpdatingStatus(true)
    const supabase = createClient()
    const patch: Partial<MaintenanceTask> = { status }
    if (status === 'completed') patch.completed_date = new Date().toISOString().split('T')[0]
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data } = await (supabase as any).from('maintenance_tasks').update(patch).eq('id', task.id).select().single() as { data: MaintenanceTask | null }
    if (data) setTask(data)
    setUpdatingStatus(false)
    if (status === 'completed') toast.success('Task completed')
    router.refresh()
  }

  async function toggleChecklistItem(index: number) {
    const updated = checklist.map((item, i) => i === index ? { ...item, done: !item.done } : item)
    setChecklist(updated)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('maintenance_tasks').update({ checklist: updated }).eq('id', task.id)
  }

  async function handleDelete() {
    const ok = await confirmDialog({
      title: 'Delete task?',
      description: 'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    })
    if (!ok) return
    setDeleting(true)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('maintenance_tasks').delete().eq('id', task.id)
    toast.success('Task deleted')
    router.push('/maintenance')
    router.refresh()
  }

  const isCompleted = task.status === 'completed'
  const isCancelled = task.status === 'cancelled'
  const isOverdue = task.status === 'overdue'
  const dueDate = task.due_date ? new Date(task.due_date) : null
  const completedDate = task.completed_date ? new Date(task.completed_date) : null
  const checklistDone = checklist.filter((c) => c.done).length

  return (
    <div className="flex flex-col">
      {/* Header */}
      <header className="glass-opaque sticky top-0 z-20 border-b border-border/50 px-4 py-4 md:px-6">
        <div className="flex items-center justify-between gap-3">
          <div className="flex items-center gap-3 min-w-0">
            <Link
              href="/maintenance"
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg glass-light text-muted-foreground hover:text-foreground transition-colors focus-ring"
            >
              <ChevronLeft className="h-4 w-4" />
            </Link>
            <div className="min-w-0">
              <h1 className={`truncate text-lg font-bold ${isCompleted || isCancelled ? 'line-through text-muted-foreground' : 'text-foreground'}`}>
                {task.title}
              </h1>
              <p className="text-xs capitalize" style={{ color: STATUS_COLORS[task.status] }}>
                {task.status.replace('_', ' ')}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Button asChild variant="ghost" size="icon">
              <Link href={`/maintenance/${task.id}/edit`} aria-label="Edit task">
                <Pencil className="h-4 w-4" />
              </Link>
            </Button>
            <Button variant="ghost" size="icon" onClick={handleDelete} loading={deleting}>
              <Trash2 className="h-4 w-4 text-destructive" />
            </Button>
          </div>
        </div>
      </header>

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6">
        {/* Status badges */}
        <div className="flex flex-wrap gap-2">
          <Badge variant={PRIORITY_VARIANTS[task.priority]} size="sm" className="capitalize">
            {task.priority} priority
          </Badge>
          <Badge variant="neutral" size="sm" className="capitalize">{task.category}</Badge>
          {roomName && (
            <Badge variant="neutral" size="sm">
              <MapPin className="h-3 w-3 mr-1" />
              {roomName}
            </Badge>
          )}
          {isOverdue && dueDate && (
            <Badge variant="critical" size="sm" className="flex items-center gap-1">
              <AlertTriangle className="h-3 w-3" />
              Overdue {formatRelativeTime(task.due_date!)}
            </Badge>
          )}
          {task.is_recurring && (
            <Badge variant="neutral" size="sm">Recurring</Badge>
          )}
          {task.is_recurring && task.status === 'completed' && task.next_due_date && (
            <Badge variant="neutral" size="sm" className="text-primary border-primary/30 bg-primary/10">
              Next: {new Date(task.next_due_date).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
            </Badge>
          )}
          {task.tags && task.tags.length > 0 && task.tags.map((t) => (
            <Badge key={t} variant="neutral" size="sm">
              <Tag className="h-3 w-3 mr-1" />
              {t}
            </Badge>
          ))}
        </div>

        {/* Quick status actions */}
        {!isCompleted && !isCancelled && (
          <div className="flex gap-2">
            {task.status === 'pending' && (
              <Button
                size="sm"
                variant="secondary"
                onClick={() => updateStatus('in_progress')}
                loading={updatingStatus}
              >
                <Clock className="h-3.5 w-3.5" />
                Start task
              </Button>
            )}
            <Button
              size="sm"
              variant="primary"
              onClick={() => updateStatus('completed')}
              loading={updatingStatus}
              className="flex-1"
            >
              <CheckCircle2 className="h-3.5 w-3.5" />
              Mark complete
            </Button>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => updateStatus('cancelled')}
              loading={updatingStatus}
              className="text-muted-foreground"
            >
              <XCircle className="h-3.5 w-3.5" />
              Cancel
            </Button>
          </div>
        )}

        {isCompleted && completedDate && (
          <div className="flex items-center gap-2 rounded-xl bg-[hsl(152,62%,38%)]/10 border border-[hsl(152,62%,38%)]/20 px-4 py-3">
            <CheckCircle2 className="h-4 w-4 text-[hsl(152,62%,48%)] shrink-0" />
            <p className="text-sm text-[hsl(152,62%,48%)]">
              Completed {completedDate.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })}
            </p>
          </div>
        )}

        {isCancelled && (
          <div className="flex items-center gap-2 rounded-xl bg-muted/30 border border-border px-4 py-3">
            <XCircle className="h-4 w-4 text-muted-foreground shrink-0" />
            <p className="text-sm text-muted-foreground">This task was cancelled</p>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => updateStatus('pending')}
              loading={updatingStatus}
              className="ml-auto text-xs"
            >
              Reopen
            </Button>
          </div>
        )}

        {/* Description */}
        {task.description && (
          <Card variant="default" padding="md">
            <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">Description</p>
            <p className="text-sm text-foreground leading-relaxed whitespace-pre-wrap">{task.description}</p>
          </Card>
        )}

        {/* Details */}
        <Card variant="default" padding="md">
          <div className="flex flex-col divide-y divide-border/40">
            {assigneeName && (
              <DetailRow icon={User} label="Assigned to">
                <span className="text-sm font-medium text-foreground">{assigneeName}</span>
              </DetailRow>
            )}
            {dueDate && (
              <DetailRow icon={Calendar} label="Due date">
                <span className={`text-sm font-medium ${isOverdue ? 'text-destructive' : 'text-foreground'}`}>
                  {dueDate.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })}
                </span>
              </DetailRow>
            )}
            {task.estimated_cost != null && (
              <DetailRow icon={DollarSign} label="Estimated cost">
                <span className="text-sm font-medium text-foreground">
                  {task.cost_currency ?? 'EUR'} {task.estimated_cost.toLocaleString()}
                </span>
              </DetailRow>
            )}
            {task.actual_cost != null && (
              <DetailRow icon={DollarSign} label="Actual cost">
                <span className="text-sm font-medium text-foreground">
                  {task.cost_currency ?? 'EUR'} {task.actual_cost.toLocaleString()}
                </span>
              </DetailRow>
            )}
            {task.estimated_hours != null && (
              <DetailRow icon={Clock} label="Estimated time">
                <span className="text-sm font-medium text-foreground">{task.estimated_hours}h</span>
              </DetailRow>
            )}
            {task.actual_hours != null && (
              <DetailRow icon={Clock} label="Actual time">
                <span className="text-sm font-medium text-foreground">{task.actual_hours}h</span>
              </DetailRow>
            )}
            {task.contractor_name && (
              <DetailRow icon={User} label="Contractor">
                <span className="text-sm font-medium text-foreground">{task.contractor_name}</span>
              </DetailRow>
            )}
            {task.contractor_phone && (
              <DetailRow icon={Phone} label="Contractor phone">
                <a href={`tel:${task.contractor_phone}`} className="text-sm font-medium text-primary hover:underline">
                  {task.contractor_phone}
                </a>
              </DetailRow>
            )}
            {task.contractor_email && (
              <DetailRow icon={Mail} label="Contractor email">
                <a href={`mailto:${task.contractor_email}`} className="text-sm font-medium text-primary hover:underline truncate max-w-[200px]">
                  {task.contractor_email}
                </a>
              </DetailRow>
            )}
            {inventoryItemName && (
              <DetailRow icon={Package} label="Inventory item">
                <Link href={`/inventory/${task.inventory_item_id}`} className="text-sm font-medium text-primary hover:underline truncate max-w-[200px]">
                  {inventoryItemName}
                </Link>
              </DetailRow>
            )}
          </div>
        </Card>

        {/* Before / After photos */}
        {(['before', 'after'] as const).map((slot) => {
          const urls: string[] = (slot === 'before' ? task.before_photo_urls : task.after_photo_urls) ?? []
          const isUploading = uploadingSlot === slot
          return (
            <Card key={slot} variant="default" padding="md">
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center gap-2">
                  <Image className="h-4 w-4 text-muted-foreground" />
                  <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground capitalize">{slot}</p>
                  {urls.length > 0 && <span className="text-[10px] text-muted-foreground">({urls.length})</span>}
                </div>
                <label className={`flex items-center gap-1.5 rounded-lg px-2.5 py-1 text-xs transition-colors cursor-pointer focus-ring ${isUploading ? 'text-muted-foreground' : 'glass-light text-muted-foreground hover:text-foreground'}`}>
                  {isUploading ? <Loader2 className="h-3 w-3 animate-spin" /> : <Camera className="h-3 w-3" />}
                  {isUploading ? 'Uploading…' : 'Add photo'}
                  <input
                    type="file"
                    accept="image/*"
                    capture="environment"
                    className="sr-only"
                    disabled={isUploading}
                    onChange={(e) => {
                      const f = e.target.files?.[0]
                      if (f) handlePhotoUpload(f, slot)
                    }}
                  />
                </label>
              </div>
              {urls.length > 0 ? (
                <div className="flex gap-2 overflow-x-auto pb-1">
                  {urls.map((url, i) => (
                    <a key={url} href={url} target="_blank" rel="noopener noreferrer">
                      <img src={url} alt={`${slot} ${i + 1}`} className="h-28 w-28 shrink-0 rounded-xl object-cover border border-border hover:opacity-80 transition-opacity" />
                    </a>
                  ))}
                </div>
              ) : (
                <div className="flex h-16 items-center justify-center rounded-xl border border-dashed border-border">
                  <p className="text-xs text-muted-foreground">No {slot} photos yet</p>
                </div>
              )}
            </Card>
          )
        })}

        {/* Checklist */}
        {checklist.length > 0 && (
          <Card variant="default" padding="md">
            <div className="flex items-center justify-between mb-3">
              <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Checklist</p>
              <span className="text-xs text-muted-foreground">{checklistDone}/{checklist.length}</span>
            </div>
            <div className="flex flex-col gap-2">
              {checklist.map((item, i) => (
                <button
                  key={i}
                  type="button"
                  onClick={() => toggleChecklistItem(i)}
                  className="flex items-center gap-3 text-left focus-ring rounded-lg"
                >
                  {item.done
                    ? <CheckSquare className="h-4 w-4 shrink-0 text-[hsl(152,62%,48%)]" />
                    : <Square className="h-4 w-4 shrink-0 text-muted-foreground" />
                  }
                  <span className={`text-sm ${item.done ? 'line-through text-muted-foreground' : 'text-foreground'}`}>
                    {item.text}
                  </span>
                </button>
              ))}
            </div>
          </Card>
        )}

        {/* Notes */}
        {task.notes && (
          <Card variant="default" padding="md">
            <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">Notes</p>
            <p className="text-sm text-foreground whitespace-pre-wrap leading-relaxed">{task.notes}</p>
          </Card>
        )}

        {/* Contractor Chat */}
        <Card variant="default" padding="none">
          <div className="flex items-center gap-2 px-4 py-3 border-b border-border/30">
            <MessageSquare className="h-4 w-4 text-muted-foreground" />
            <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Contractor Chat</p>
            {messages.length > 0 && <span className="text-xs text-muted-foreground ml-auto">{messages.length} messages</span>}
          </div>
          <div className="flex flex-col gap-2 max-h-72 overflow-y-auto p-4">
            {loadingMsgs ? (
              <div className="flex justify-center py-4"><Loader2 className="h-4 w-4 animate-spin text-muted-foreground" /></div>
            ) : messages.length === 0 ? (
              <p className="text-center text-xs text-muted-foreground py-4">No messages yet. Start the conversation.</p>
            ) : (
              messages.map((msg) => {
                const isMine = msg.sender_id === userId
                return (
                  <div key={msg.id} className={`flex ${isMine ? 'justify-end' : 'justify-start'}`}>
                    <div className={`max-w-[75%] rounded-2xl px-3 py-2 text-sm ${isMine ? 'bg-primary text-white rounded-br-sm' : 'bg-muted text-foreground rounded-bl-sm'}`}>
                      <p>{msg.content}</p>
                      <p className={`text-[10px] mt-0.5 ${isMine ? 'text-white/60' : 'text-muted-foreground'}`}>
                        {new Date(msg.created_at).toLocaleTimeString('en', { hour: '2-digit', minute: '2-digit' })}
                      </p>
                    </div>
                  </div>
                )
              })
            )}
            <div ref={chatEndRef} />
          </div>
          {userId && (
            <form onSubmit={sendMessage} className="flex items-center gap-2 px-4 py-3 border-t border-border/30">
              <input
                value={msgText}
                onChange={(e) => setMsgText(e.target.value)}
                placeholder="Type a message…"
                className="flex-1 rounded-xl border border-border/50 bg-background/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
              <button
                type="submit"
                disabled={sendingMsg || !msgText.trim()}
                className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary text-white disabled:opacity-50 transition-opacity"
              >
                {sendingMsg ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
              </button>
            </form>
          )}
        </Card>
      </div>
    </div>
  )
}

function DetailRow({
  icon: Icon,
  label,
  children,
}: {
  icon: React.ComponentType<{ className?: string }>
  label: string
  children: React.ReactNode
}) {
  return (
    <div className="flex items-center gap-3 py-3 first:pt-0 last:pb-0">
      <Icon className="h-4 w-4 shrink-0 text-muted-foreground" />
      <div className="flex flex-1 items-center justify-between gap-4">
        <span className="text-sm text-muted-foreground">{label}</span>
        {children}
      </div>
    </div>
  )
}
