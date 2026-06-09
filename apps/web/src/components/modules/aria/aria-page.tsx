'use client'

import * as React from 'react'
import { Sparkles, Send, RotateCcw, Lightbulb, Wrench, Zap, Shield } from 'lucide-react'
import { cn } from '@/lib/utils'

interface AriaPageProps {
  userId: string
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

export function AriaPage({ userId: _userId }: AriaPageProps) {
  const [messages, setMessages] = React.useState<Message[]>([WELCOME_MESSAGE])
  const [input, setInput] = React.useState('')
  const [isThinking, setIsThinking] = React.useState(false)
  const bottomRef = React.useRef<HTMLDivElement>(null)
  const inputRef = React.useRef<HTMLTextAreaElement>(null)

  React.useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

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

    // Placeholder response — will connect to Claude API in Phase 4
    setTimeout(() => {
      const ariaResponse: Message = {
        id: crypto.randomUUID(),
        role: 'assistant',
        content: `I understand you're asking about: **"${text.trim()}"**

ARIA's full AI capabilities will be activated in Phase 4 when connected to the Claude API. I'll be able to:

• Analyze your property's specific data and history
• Provide personalized recommendations
• Learn your home's patterns over time
• Generate detailed maintenance plans

For now, I'm here as a preview of what's coming. Stay tuned! 🏠`,
        timestamp: new Date(),
      }
      setMessages((prev) => [...prev, ariaResponse])
      setIsThinking(false)
    }, 1500)
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      sendMessage(input)
    }
  }

  function handleReset() {
    setMessages([WELCOME_MESSAGE])
    setInput('')
    inputRef.current?.focus()
  }

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

        {/* Suggested prompts (only show when only welcome message) */}
        {messages.length === 1 && (
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
            style={{
              height: 'auto',
            }}
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
