'use client'

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { cn } from '@/lib/utils'

const LOCALES = [
  { code: 'en', label: 'English', flag: '🇬🇧' },
  { code: 'ro', label: 'Română', flag: '🇷🇴' },
  { code: 'fr', label: 'Français', flag: '🇫🇷' },
  { code: 'nl', label: 'Nederlands', flag: '🇳🇱' },
  { code: 'it', label: 'Italiano', flag: '🇮🇹' },
  { code: 'pl', label: 'Polski', flag: '🇵🇱' },
]

export function LanguageSettings() {
  return (
    <div className="flex flex-col gap-6 max-w-lg">
      <Card variant="default" padding="lg">
        <CardHeader>
          <CardTitle>Interface Language</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 gap-2">
            {LOCALES.map(({ code, label, flag }) => (
              <button
                key={code}
                type="button"
                disabled
                className={cn(
                  'flex items-center gap-3 rounded-xl px-4 py-3 text-sm transition-colors',
                  code === 'en'
                    ? 'glass-standard text-foreground font-medium ring-2 ring-primary/60'
                    : 'glass-light text-muted-foreground opacity-60 cursor-not-allowed'
                )}
              >
                <span className="text-lg">{flag}</span>
                <span>{label}</span>
                {code !== 'en' && (
                  <span className="ml-auto text-[10px] text-muted-foreground">Soon</span>
                )}
              </button>
            ))}
          </div>
          <p className="mt-3 text-xs text-muted-foreground">
            Additional languages are coming soon. Currently English is the only fully supported language.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
