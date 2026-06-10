'use client'

import * as React from 'react'

type ToastVariant = 'default' | 'success' | 'warning' | 'destructive' | 'info'

interface ToastOptions {
  title: string
  description?: string
  variant?: ToastVariant
  duration?: number
}

interface ToastItem extends ToastOptions {
  id: string
  open: boolean
}

type ToastAction =
  | { type: 'ADD'; toast: ToastItem }
  | { type: 'UPDATE'; id: string; toast: Partial<ToastItem> }
  | { type: 'DISMISS'; id: string }
  | { type: 'REMOVE'; id: string }

const TOAST_LIMIT = 4
const TOAST_REMOVE_DELAY = 1000

let count = 0
function genId() {
  count = (count + 1) % Number.MAX_SAFE_INTEGER
  return count.toString()
}

const toastTimeouts = new Map<string, ReturnType<typeof setTimeout>>()

function addToRemoveQueue(toastId: string, dispatch: React.Dispatch<ToastAction>) {
  if (toastTimeouts.has(toastId)) return
  const timeout = setTimeout(() => {
    toastTimeouts.delete(toastId)
    dispatch({ type: 'REMOVE', id: toastId })
  }, TOAST_REMOVE_DELAY)
  toastTimeouts.set(toastId, timeout)
}

function reducer(state: ToastItem[], action: ToastAction): ToastItem[] {
  switch (action.type) {
    case 'ADD':
      return [action.toast, ...state].slice(0, TOAST_LIMIT)
    case 'UPDATE':
      return state.map((t) => t.id === action.id ? { ...t, ...action.toast } : t)
    case 'DISMISS':
      return state.map((t) => t.id === action.id ? { ...t, open: false } : t)
    case 'REMOVE':
      return state.filter((t) => t.id !== action.id)
    default:
      return state
  }
}

// Global listeners so toast can be called outside React components
type Listener = (state: ToastItem[]) => void
let memoryState: ToastItem[] = []
const listeners: Set<Listener> = new Set()

function dispatch(action: ToastAction) {
  memoryState = reducer(memoryState, action)
  listeners.forEach((l) => l(memoryState))
}

export function toast(options: ToastOptions) {
  const id = genId()
  const duration = options.duration ?? 4000

  dispatch({ type: 'ADD', toast: { ...options, id, open: true } })

  const dismissTimer = setTimeout(() => {
    dispatch({ type: 'DISMISS', id })
    addToRemoveQueue(id, dispatch)
  }, duration)

  return {
    id,
    dismiss: () => {
      clearTimeout(dismissTimer)
      dispatch({ type: 'DISMISS', id })
      addToRemoveQueue(id, dispatch)
    },
    update: (opts: Partial<ToastOptions>) => dispatch({ type: 'UPDATE', id, toast: opts }),
  }
}

// Semantic helpers — the canonical way to fire toasts across all modules.
toast.success = (title: string, description?: string) =>
  toast({ title, description, variant: 'success' })
toast.warning = (title: string, description?: string) =>
  toast({ title, description, variant: 'warning' })
toast.error = (title: string, description?: string) =>
  toast({ title, description, variant: 'destructive' })
toast.info = (title: string, description?: string) =>
  toast({ title, description, variant: 'info' })

export function useToast() {
  const [toasts, setToasts] = React.useState<ToastItem[]>(memoryState)

  React.useEffect(() => {
    listeners.add(setToasts)
    return () => { listeners.delete(setToasts) }
  }, [])

  return {
    toasts,
    toast,
    dismiss: (id: string) => {
      dispatch({ type: 'DISMISS', id })
      addToRemoveQueue(id, dispatch)
    },
  }
}
