import { defineRouting } from 'next-intl/routing'

export const routing = defineRouting({
  locales: ['en', 'ro', 'fr', 'nl', 'it', 'pl'],
  defaultLocale: 'en',
  localePrefix: 'as-needed',
})
