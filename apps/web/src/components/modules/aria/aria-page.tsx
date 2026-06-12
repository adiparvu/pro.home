'use client'

import * as React from 'react'
import { Sparkles, Send, RotateCcw, Copy, Check, Zap } from 'lucide-react'
import { cn } from '@/lib/utils'
import { createClient } from '@/lib/supabase/client'
import type { AriaMessage } from '@/lib/supabase/types'
import type { AriaContextHints } from '@/app/(app)/aria/page'
import { toast } from '@/hooks/use-toast'

interface AriaPageProps {
  userId: string
  propertyId: string | null
  initialMessages: AriaMessage[]
  contextHints?: AriaContextHints
}

interface Message {
  id: string
  role: 'user' | 'assistant'
  content: string
  timestamp: Date
}

const MONTH_NAMES = ['January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December']

function buildSuggestedPrompts(hints?: AriaContextHints): string[] {
  const prompts: string[] = []
  const month = hints?.currentMonth ?? new Date().getMonth() + 1

  if ((hints?.overdueTaskCount ?? 0) > 0) {
    const n = hints!.overdueTaskCount
    prompts.push(`I have ${n} overdue task${n > 1 ? 's' : ''} — where should I start?`)
  }
  if (hints?.hasExpiringWarranties) {
    prompts.push('Which of my warranties are expiring soon?')
  }
  if (hints?.hasEnergyData) {
    prompts.push('Help me reduce my energy consumption')
  }

  // Seasonal / month-based fallbacks
  const seasonal: Record<number, string> = {
    1: 'What winter maintenance should I do now?',
    2: 'How do I prepare my home for spring?',
    3: 'What spring home maintenance should I do?',
    4: 'What should I service before summer?',
    5: 'How do I check my AC before summer?',
    6: 'What summer home maintenance is important?',
    7: 'How do I protect my home in the heat?',
    8: 'How do I prepare my home for autumn?',
    9: 'What autumn maintenance should I prioritize?',
    10: 'How do I winterize my heating system?',
    11: 'How do I prepare my pipes for freezing?',
    12: 'What should I check before the new year?',
  }

  const defaults = [
    `What should I check in ${MONTH_NAMES[(month - 1) % 12]}?`,
    seasonal[month] ?? 'What maintenance should I do this month?',
    'How can I improve my home security?',
    'Why is my energy bill so high?',
    'Give me a seasonal home maintenance checklist',
  ]

  for (const p of defaults) {
    if (prompts.length >= 4) break
    if (!prompts.includes(p)) prompts.push(p)
  }

  return prompts.slice(0, 4)
}

const WELCOME_MESSAGE: Message = {
  id: 'welcome',
  role: 'assistant',
  content: `Hello! I'm ARIA, your AI property brain. I can help you with:

• **Maintenance planning** — when to service appliances, seasonal checklists
• **Energy optimization** — reduce bills and carbon footprint
• **Security advice** — protect your home and family
• **Cost estimates** — budget for repairs and upgrades
• **Property questions** — anything about your home

What would you like to know today?`,
  timestamp: new Date(),
}

function dbToMessage(m: AriaMessage): Message {
  return { id: m.id, role: m.role, content: m.content, timestamp: new Date(m.created_at) }
}

export function AriaPage({ userId, propertyId, initialMessages, contextHints }: AriaPageProps) {
  const [messages, setMessages] = React.useState<Message[]>(() => {
    if (initialMessages.length > 0) return initialMessages.map(dbToMessage)
    return [WELCOME_MESSAGE]
  })
  const [input, setInput] = React.useState('')
  const [isThinking, setIsThinking] = React.useState(false)
  const [taskCreating, setTaskCreating] = React.useState(false)
  const messagesContainerRef = React.useRef<HTMLDivElement>(null)
  const bottomRef = React.useRef<HTMLDivElement>(null)
  const inputRef = React.useRef<HTMLTextAreaElement>(null)

  const suggestedPrompts = React.useMemo(() => buildSuggestedPrompts(contextHints), [contextHints])

  React.useEffect(() => {
    // Scroll within the messages container — do NOT use scrollIntoView which
    // falls back to window scroll and pushes the sticky header off screen.
    const container = messagesContainerRef.current
    if (container) {
      container.scrollTop = container.scrollHeight
    }
  }, [messages])

  async function persistMessage(role: 'user' | 'assistant', content: string) {
    if (!propertyId) return
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('aria_messages').insert({
      user_id: userId,
      property_id: propertyId,
      role,
      content,
    })
  }

  async function sendMessage(text: string) {
    if (!text.trim() || isThinking) return

    const userMessage: Message = {
      id: crypto.randomUUID(),
      role: 'user',
      content: text.trim(),
      timestamp: new Date(),
    }

    setMessages((prev) => [...prev, userMessage])
    setInput('')
    setIsThinking(true)

    await persistMessage('user', text.trim())

    const history = [...messages, userMessage]
      .filter((m) => m.id !== 'welcome')
      .map((m) => ({ role: m.role, content: m.content }))

    try {
      const res = await fetch('/api/aria', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ messages: history }),
      })

      if (!res.ok) {
        const data = await res.json() as { error?: string }
        setMessages((prev) => [...prev, {
          id: crypto.randomUUID(),
          role: 'assistant',
          content: data.error ?? 'Something went wrong. Please try again.',
          timestamp: new Date(),
        }])
        return
      }

      // Start streaming — add empty assistant message immediately
      const ariaId = crypto.randomUUID()
      setMessages((prev) => [...prev, {
        id: ariaId,
        role: 'assistant',
        content: '',
        timestamp: new Date(),
      }])
      setIsThinking(false)

      const reader = res.body!.getReader()
      const decoder = new TextDecoder()
      let fullContent = ''

      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        const chunk = decoder.decode(value, { stream: true })
        fullContent += chunk
        setMessages((prev) =>
          prev.map((m) => m.id === ariaId ? { ...m, content: fullContent } : m)
        )
      }

      if (fullContent) {
        await persistMessage('assistant', fullContent)
      }
    } catch {
      setMessages((prev) => [...prev, {
        id: crypto.randomUUID(),
        role: 'assistant',
        content: 'Network error — please check your connection and try again.',
        timestamp: new Date(),
      }])
    } finally {
      setIsThinking(false)
    }
  }

  async function handleCreateTask() {
    const text = input.trim()
    if (!text || taskCreating) return
    setTaskCreating(true)
    try {
      const res = await fetch('/api/ai/create-task', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text }),
      })
      const json = await res.json() as { title?: string; task_id?: string; error?: string }
      if (!res.ok || json.error) {
        toast({ title: 'Could not create task', description: json.error ?? 'Unknown error', variant: 'destructive' })
        return
      }
      toast({ title: 'Task created', description: json.title ?? 'New maintenance task added' })
      setInput('')
      inputRef.current?.focus()
    } catch (err) {
      toast({ title: 'Error', description: String(err), variant: 'destructive' })
    } finally {
      setTaskCreating(false)
    }
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      sendMessage(input)
    }
  }

  async function handleReset() {
    setMessages([WELCOME_MESSAGE])
    setInput('')
    inputRef.current?.focus()
    if (propertyId) {
      const supabase = createClient()
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      await (supabase as any)
        .from('aria_messages')
        .delete()
        .eq('user_id', userId)
        .eq('property_id', propertyId)
    }
  }

  const showSuggestions = messages.length === 1 && messages[0]?.id === 'welcome'

  return (
    <div className="flex flex-1 flex-col min-h-0">
      {/* Header */}
      <header className="glass-opaque sticky top-0 z-20 border-b border-border/50 px-4 py-4 md:px-6">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div
              className="flex h-9 w-9 items-center justify-center rounded-xl"
              style={{ background: 'hsl(280 68% 47% / 0.20)' }}
            >
              <Sparkles className="h-5 w-5" style={{ color: 'hsl(280, 68%, 57%)' }} />
            </div>
            <div>
              <p className="text-sm font-bold text-foreground">ARIA</p>
              <p className="text-[10px] text-muted-foreground">Property Brain</p>
            </div>
          </div>
          <button
            type="button"
            onClick={handleReset}
            className="flex h-8 w-8 items-center justify-center rounded-lg glass-light text-muted-foreground hover:text-foreground transition-colors focus-ring"
            aria-label="New conversation"
          >
            <RotateCcw className="h-3.5 w-3.5" />
          </button>
        </div>
      </header>

      {/* Messages — min-h-0 allows flex child to shrink and scroll internally */}
      <div ref={messagesContainerRef} className="flex-1 min-h-0 overflow-y-auto px-4 py-4 md:px-6 space-y-4 pb-[180px] md:pb-32">
        {messages.map((message) => (
          <MessageBubble key={message.id} message={message} />
        ))}

        {isThinking && <ThinkingBubble />}

        {showSuggestions && (
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 mt-4">
            {suggestedPrompts.map((text) => (
              <button
                key={text}
                type="button"
                onClick={() => sendMessage(text)}
                className="flex items-start gap-2 rounded-xl glass-light px-3 py-2.5 text-sm text-muted-foreground hover:text-foreground transition-colors text-left focus-ring"
              >
                <Sparkles className="h-3.5 w-3.5 shrink-0 mt-0.5" style={{ color: 'hsl(280, 68%, 57%)' }} />
                {text}
              </button>
            ))}
          </div>
        )}

        <div ref={bottomRef} />
      </div>

      {/* Input */}
      <div className="fixed bottom-[88px] left-0 right-0 z-20 md:bottom-0 md:left-[72px] lg:left-[260px] glass-opaque border-t border-border/50 px-4 py-3 md:px-6">
        <div className="max-w-3xl mx-auto space-y-2">
          {/* Quick task chip */}
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => {
                if (!input.trim()) {
                  setInput('Create task: ')
                  inputRef.current?.focus()
                } else {
                  handleCreateTask()
                }
              }}
              disabled={taskCreating}
              className={cn(
                'flex items-center gap-1.5 rounded-full border border-border/50 glass-light px-3 py-1 text-xs text-muted-foreground hover:text-foreground transition-colors focus-ring',
                taskCreating && 'opacity-50 cursor-not-allowed'
              )}
            >
              <Zap className="h-3 w-3 shrink-0" style={{ color: 'hsl(45,80%,52%)' }} />
              {taskCreating ? 'Creating…' : input.trim() ? '⚡ Create task from input' : '⚡ Create task'}
            </button>
          </div>
        <div className="flex items-end gap-2">
          <textarea
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Ask ARIA anything about your home…"
            rows={1}
            className="flex-1 resize-none rounded-xl border border-border glass-light px-4 py-2.5 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/60 min-h-[44px] max-h-[120px] overflow-y-auto"
          />
          <button
            type="button"
            onClick={() => sendMessage(input)}
            disabled={!input.trim() || isThinking}
            className={cn(
              'flex h-11 w-11 shrink-0 items-center justify-center rounded-xl transition-all duration-fast focus-ring',
              input.trim() && !isThinking
                ? 'text-white shadow-glow-aria'
                : 'glass-light text-muted-foreground cursor-not-allowed opacity-50'
            )}
            style={input.trim() && !isThinking ? { background: 'hsl(280, 68%, 47%)' } : undefined}
            aria-label="Send message"
          >
            <Send className="h-4 w-4" />
          </button>
        </div>
        </div>
      </div>
    </div>
  )
}

function MessageBubble({ message }: { message: Message }) {
  const isUser = message.role === 'user'
  const [copied, setCopied] = React.useState(false)

  function handleCopy() {
    const plain = message.content.replace(/\*\*(.*?)\*\*/g, '$1')
    navigator.clipboard.writeText(plain)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <div className={cn('flex gap-3 group', isUser && 'flex-row-reverse')}>
      {!isUser && (
        <div
          className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full"
          style={{ background: 'hsl(280 68% 47% / 0.20)' }}
        >
          <Sparkles className="h-4 w-4" style={{ color: 'hsl(280, 68%, 57%)' }} />
        </div>
      )}
      <div className="flex flex-col gap-1 max-w-[85%]">
        <div
          className={cn(
            'rounded-2xl px-4 py-3 text-sm',
            isUser
              ? 'glass-standard text-foreground rounded-tr-sm'
              : 'glass-light text-foreground rounded-tl-sm'
          )}
        >
          <FormattedContent content={message.content} />
        </div>
        {!isUser && message.content && (
          <button
            type="button"
            onClick={handleCopy}
            className="flex items-center gap-1 self-start text-[11px] text-muted-foreground hover:text-foreground transition-colors opacity-0 group-hover:opacity-100 px-1"
          >
            {copied
              ? <><Check className="h-3 w-3" /> Copied</>
              : <><Copy className="h-3 w-3" /> Copy</>
            }
          </button>
        )}
      </div>
    </div>
  )
}

function FormattedContent({ content }: { content: string }) {
  if (!content) return <span className="inline-block h-4 w-1 bg-current opacity-70 animate-pulse" />
  const parts = content.split(/(\*\*.*?\*\*)/g)
  return (
    <p className="whitespace-pre-wrap">
      {parts.map((part, i) =>
        part.startsWith('**') && part.endsWith('**') ? (
          <strong key={i}>{part.slice(2, -2)}</strong>
        ) : (
          <React.Fragment key={i}>{part}</React.Fragment>
        )
      )}
    </p>
  )
}

function ThinkingBubble() {
  return (
    <div className="flex gap-3">
      <div
        className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full"
        style={{ background: 'hsl(280 68% 47% / 0.20)' }}
      >
        <Sparkles className="h-4 w-4" style={{ color: 'hsl(280, 68%, 57%)' }} />
      </div>
      <div className="glass-light rounded-2xl rounded-tl-sm px-4 py-3">
        <div className="flex gap-1 items-center h-5">
          {[0, 1, 2].map((i) => (
            <div
              key={i}
              className="h-1.5 w-1.5 rounded-full animate-pulse-soft"
              style={{ background: 'hsl(280, 68%, 57%)', animationDelay: `${i * 200}ms` }}
            />
          ))}
        </div>
      </div>
    </div>
  )
}
