'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { useLocale } from 'next-intl'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { toast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'

const LOCALES = [
  { code: 'en', label: 'English', flag: '🇬🇧', available: true },
  { code: 'ro', label: 'Română', flag: '🇷🇴', available: true },
  { code: 'fr', label: 'Français', flag: '🇫🇷', available: true },
  { code: 'es', label: 'Español', flag: '🇪🇸', available: true },
  { code: 'de', label: 'Deutsch', flag: '🇩🇪', available: true },
  { code: 'nl', label: 'Nederlands', flag: '🇳🇱', available: false },
  { code: 'it', label: 'Italiano', flag: '🇮🇹', available: false },
  { code: 'pl', label: 'Polski', flag: '🇵🇱', available: false },
]

export function LanguageSettings() {
  const router = useRouter()
  const activeLocale = useLocale()

  function selectLocale(code: string) {
    if (code === activeLocale) return
    document.cookie = `NEXT_LOCALE=${code}; path=/; max-age=${60 * 60 * 24 * 365}; samesite=lax`
    const msgs: Record<string, string> = {
      ro: 'Limba a fost schimbată',
      fr: 'Langue mise à jour',
      es: 'Idioma actualizado',
      de: 'Sprache aktualisiert',
    }
    toast.success(msgs[code] ?? 'Language updated')
    router.refresh()
  }

  return (
    <div className="flex flex-col gap-6 max-w-lg">
      <Card variant="default" padding="lg">
        <CardHeader>
          <CardTitle>Interface Language</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 gap-2">
            {LOCALES.map(({ code, label, flag, available }) => (
              <button
                key={code}
                type="button"
                disabled={!available}
                onClick={() => selectLocale(code)}
                className={cn(
                  'flex items-center gap-3 rounded-xl px-4 py-3 text-sm transition-colors focus-ring',
                  code === activeLocale
                    ? 'glass-standard text-foreground font-medium ring-2 ring-primary/60'
                    : available
                      ? 'glass-light text-muted-foreground hover:text-foreground'
                      : 'glass-light text-muted-foreground opacity-60 cursor-not-allowed'
                )}
              >
                <span className="text-lg">{flag}</span>
                <span>{label}</span>
                {!available && (
                  <span className="ml-auto text-[10px] text-muted-foreground">Soon</span>
                )}
              </button>
            ))}
          </div>
          <p className="mt-3 text-xs text-muted-foreground">
            5 languages supported. Dutch, Italian, and Polish coming soon.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
