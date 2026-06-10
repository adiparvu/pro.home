import { Sparkles } from 'lucide-react'

const MODULE_ICONS: Record<string, string> = {
  documents: '📄',
  finances: '💳',
  marketplace: '🛒',
  garden: '🌱',
}

interface ComingSoonProps {
  module: string
}

export function ComingSoon({ module }: ComingSoonProps) {
  const emoji = MODULE_ICONS[module] ?? '🚀'

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-4 px-4 py-20 text-center">
      <div className="flex h-20 w-20 items-center justify-center rounded-3xl glass-standard text-4xl">
        {emoji}
      </div>
      <div>
        <p className="text-xl font-bold text-foreground capitalize">{module}</p>
        <p className="mt-1 text-sm text-muted-foreground max-w-[260px]">
          This module is under active development and will be available soon.
        </p>
      </div>
      <div className="flex items-center gap-2 rounded-full glass-light px-4 py-2 text-xs text-muted-foreground">
        <Sparkles className="h-3 w-3" />
        Coming in the next release
      </div>
    </div>
  )
}
