'use client'

import * as React from 'react'
import { Sparkles, Send, RotateCcw, Lightbulb, Wrench, Zap, Shield } from 'lucide-react'
import { cn } from '@/lib/utils'
import { createClient } from '@/lib/supabase/client'
import type { AriaMessage } from '@/lib/supabase/types'

interface AriaPageProps {
  userId: string
  propertyId: string | null
  initialMessages: AriaMessage[]
}

interface Message {
  id: string
  role: 'user' | 'assistant'
  content: string
  timestamp: Date
}

const SUGGESTED_PROMPTS = [
  { icon: Lightbulb, text: 'What should I check this month?' },
  { icon: Wrench, text: 'How do I winterize my heating system?' },
  { icon: Zap, text: 'Why is my energy bill so high?' },
  { icon: Shield, text: 'How can I improve my home security?' },
]

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

export function AriaPage({ userId, propertyId, initialMessages }: AriaPageProps) {
  const [messages, setMessages] = React.useState<Message[]>(() => {
    if (initialMessages.length > 0) return initialMessages.map(dbToMessage)
    return [WELCOME_MESSAGE]
  })
  const [input, setInput] = React.useState('')
  const [isThinking, setIsThinking] = React.useState(false)
  const bottomRef = React.useRef<HTMLDivElement>(null)
  const inputRef = React.useRef<HTMLTextAreaElement>(null)

  React.useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
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

    // Persist user message
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

      const data = await res.json() as { content?: string; error?: string }
      const responseContent = data.error ?? data.content ?? 'Sorry, something went wrong. Please try again.'

      const ariaResponse: Message = {
        id: crypto.randomUUID(),
        role: 'assistant',
        content: responseContent,
        timestamp: new Date(),
      }
      setMessages((prev) => [...prev, ariaResponse])

      // Persist ARIA response
      await persistMessage('assistant', responseContent)
    } catch {
      setMessages((prev) => [
        ...prev,
        {
          id: crypto.randomUUID(),
          role: 'assistant',
          content: 'Network error — please check your connection and try again.',
          timestamp: new Date(),
        },
      ])
    } finally {
      setIsThinking(false)
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

    // Clear persisted messages for this user+property
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
    <div className="flex flex-1 flex-col">
      {/* Header */}
      <header className="glass-opaque sticky top-0 z-20 border-b border-border/50 px-4 py-4 md:px-6">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-xl"
              style={{ background: 'hsl(280, 68%, 47% / 0.20)' }}>
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

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-4 py-4 md:px-6 space-y-4 pb-[180px] md:pb-32">
        {messages.map((message) => (
          <MessageBubble key={message.id} message={message} />
        ))}

        {isThinking && <ThinkingBubble />}

        {showSuggestions && (
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 mt-4">
            {SUGGESTED_PROMPTS.map(({ icon: Icon, text }) => (
              <button
                key={text}
                type="button"
                onClick={() => sendMessage(text)}
                className="flex items-center gap-2 rounded-xl glass-light px-3 py-2.5 text-sm text-muted-foreground hover:text-foreground transition-colors text-left focus-ring"
              >
                <Icon className="h-4 w-4 shrink-0" />
                {text}
              </button>
            ))}
          </div>
        )}

        <div ref={bottomRef} />
      </div>

      {/* Input */}
      <div className="fixed bottom-[88px] left-0 right-0 z-20 md:bottom-0 md:left-[72px] lg:left-[260px] glass-opaque border-t border-border/50 px-4 py-3 md:px-6">
        <div className="flex items-end gap-2 max-w-3xl mx-auto">
          <textarea
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Ask ARIA anything about your home..."
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
            style={input.trim() && !isThinking ? {
              background: 'hsl(280, 68%, 47%)',
            } : undefined}
            aria-label="Send message"
          >
            <Send className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  )
}

function MessageBubble({ message }: { message: Message }) {
  const isUser = message.role === 'user'

  return (
    <div className={cn('flex gap-3', isUser && 'flex-row-reverse')}>
      {!isUser && (
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full"
          style={{ background: 'hsl(280, 68%, 47% / 0.20)' }}>
          <Sparkles className="h-4 w-4" style={{ color: 'hsl(280, 68%, 57%)' }} />
        </div>
      )}
      <div
        className={cn(
          'max-w-[85%] rounded-2xl px-4 py-3 text-sm',
          isUser
            ? 'glass-standard text-foreground rounded-tr-sm'
            : 'glass-light text-foreground rounded-tl-sm'
        )}
      >
        <FormattedContent content={message.content} />
      </div>
    </div>
  )
}

function FormattedContent({ content }: { content: string }) {
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
      <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full"
        style={{ background: 'hsl(280, 68%, 47% / 0.20)' }}>
        <Sparkles className="h-4 w-4" style={{ color: 'hsl(280, 68%, 57%)' }} />
      </div>
      <div className="glass-light rounded-2xl rounded-tl-sm px-4 py-3">
        <div className="flex gap-1 items-center h-5">
          {[0, 1, 2].map((i) => (
            <div
              key={i}
              className="h-1.5 w-1.5 rounded-full animate-pulse-soft"
              style={{
                background: 'hsl(280, 68%, 57%)',
                animationDelay: `${i * 200}ms`,
              }}
            />
          ))}
        </div>
      </div>
    </div>
  )
}
