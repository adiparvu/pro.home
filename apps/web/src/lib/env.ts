/**
 * Centralised environment variable validation.
 * Import this module in server-only code to get typed, validated env vars.
 * Missing required vars throw at module load time — fail fast before serving traffic.
 */

import { z } from 'zod'

const serverSchema = z.object({
  // Supabase — required for all DB / auth operations
  NEXT_PUBLIC_SUPABASE_URL: z.string().url('NEXT_PUBLIC_SUPABASE_URL must be a valid URL'),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1, 'NEXT_PUBLIC_SUPABASE_ANON_KEY is required'),

  // ARIA — optional; ARIA returns 503 gracefully when missing
  ANTHROPIC_API_KEY: z.string().optional(),

  // Site URL — needed for invite links and auth redirects in production
  NEXT_PUBLIC_SITE_URL: z.string().url().optional(),

  // Sentry — fully optional; error tracking silently disabled when unset
  NEXT_PUBLIC_SENTRY_DSN: z.string().url().optional(),
  SENTRY_ORG: z.string().optional(),
  SENTRY_PROJECT: z.string().optional(),
  SENTRY_AUTH_TOKEN: z.string().optional(),

  // Upstash Redis — optional; rate limiter degrades to in-memory when unset
  UPSTASH_REDIS_REST_URL: z.string().url().optional(),
  UPSTASH_REDIS_REST_TOKEN: z.string().optional(),

  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
})

function validateEnv() {
  const parsed = serverSchema.safeParse(process.env)
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((i) => `  • ${i.path.join('.')}: ${i.message}`)
      .join('\n')
    throw new Error(`\n❌ Invalid environment variables:\n${issues}\n`)
  }
  return parsed.data
}

// Validate once at module load; memoise the result
let _env: z.infer<typeof serverSchema> | undefined

export function getEnv() {
  if (!_env) _env = validateEnv()
  return _env
}

// Convenience re-export for the most common vars
export const env = {
  get supabaseUrl() { return process.env.NEXT_PUBLIC_SUPABASE_URL! },
  get supabaseAnonKey() { return process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY! },
  get anthropicApiKey() { return process.env.ANTHROPIC_API_KEY },
  get siteUrl() { return process.env.NEXT_PUBLIC_SITE_URL },
  get sentryDsn() { return process.env.NEXT_PUBLIC_SENTRY_DSN },
  get isDev() { return process.env.NODE_ENV === 'development' },
  get isProd() { return process.env.NODE_ENV === 'production' },
}
