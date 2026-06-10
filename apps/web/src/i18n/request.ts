import { getRequestConfig } from 'next-intl/server'
import type { AbstractIntlMessages } from 'next-intl'
import { cookies } from 'next/headers'

export const SUPPORTED_LOCALES = ['en', 'ro'] as const
export const LOCALE_COOKIE = 'NEXT_LOCALE'

/**
 * Cookie-based locale (no URL prefixes): the language picker writes
 * NEXT_LOCALE and refreshes; everything else falls back to English.
 */
type Messages = Record<string, unknown>

function deepMerge(base: Messages, override: Messages): Messages {
  const result: Messages = { ...base }
  for (const [key, value] of Object.entries(override)) {
    if (
      value && typeof value === 'object' && !Array.isArray(value) &&
      result[key] && typeof result[key] === 'object'
    ) {
      result[key] = deepMerge(result[key] as Messages, value as Messages)
    } else {
      result[key] = value
    }
  }
  return result
}

export default getRequestConfig(async () => {
  const store = await cookies()
  let locale = store.get(LOCALE_COOKIE)?.value ?? 'en'
  if (!SUPPORTED_LOCALES.includes(locale as (typeof SUPPORTED_LOCALES)[number])) {
    locale = 'en'
  }

  const english = (await import('./locales/en.json')).default as Messages
  const messages =
    locale === 'en'
      ? english
      : deepMerge(english, (await import(`./locales/${locale}.json`)).default as Messages)

  return { locale, messages: messages as AbstractIntlMessages }
})
