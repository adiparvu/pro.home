/**
 * Sliding-window in-memory rate limiter.
 *
 * Works correctly for single-process runtimes (local dev, single Vercel instance).
 * For true multi-instance production, replace the store with an Upstash Redis client:
 *   https://github.com/upstash/ratelimit-js
 *
 * To upgrade: `pnpm add @upstash/ratelimit @upstash/redis` and set
 *   UPSTASH_REDIS_REST_URL + UPSTASH_REDIS_REST_TOKEN in environment.
 */

type Window = { timestamps: number[] }
const store = new Map<string, Window>()

export interface RateLimitResult {
  allowed: boolean
  remaining: number
  retryAfter: number // seconds until limit resets, 0 if allowed
}

/**
 * @param key       Unique identifier (e.g. user ID + route)
 * @param limit     Max requests allowed in the window
 * @param windowSec Window size in seconds
 */
export function checkRateLimit(
  key: string,
  limit: number,
  windowSec: number,
): RateLimitResult {
  const now = Date.now()
  const windowMs = windowSec * 1000
  const cutoff = now - windowMs

  const window = store.get(key) ?? { timestamps: [] }
  // Drop timestamps outside the window
  window.timestamps = window.timestamps.filter((t) => t > cutoff)

  if (window.timestamps.length >= limit) {
    const oldest = window.timestamps[0] ?? now
    const retryAfter = Math.ceil((oldest + windowMs - now) / 1000)
    store.set(key, window)
    return { allowed: false, remaining: 0, retryAfter }
  }

  window.timestamps.push(now)
  store.set(key, window)
  return { allowed: true, remaining: limit - window.timestamps.length, retryAfter: 0 }
}
