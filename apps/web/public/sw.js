// PRV HOUSE Service Worker
// Cache-first for immutable static assets; network-first for everything else.

const CACHE_NAME = 'prv-house-v1'
const OFFLINE_URL = '/offline'

// ─── Install ─────────────────────────────────────────────────────────────────
self.addEventListener('install', (event) => {
  self.skipWaiting()
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll([OFFLINE_URL]))
  )
})

// ─── Activate ────────────────────────────────────────────────────────────────
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
      )
      .then(() => self.clients.claim())
  )
})

// ─── Fetch ───────────────────────────────────────────────────────────────────
self.addEventListener('fetch', (event) => {
  const { request } = event
  const url = new URL(request.url)

  // Only handle GET over http(s)
  if (request.method !== 'GET' || !url.protocol.startsWith('http')) return

  // Cache-first for Next.js immutable static assets (content-hashed filenames)
  if (url.pathname.startsWith('/_next/static/')) {
    event.respondWith(cacheFirst(request))
    return
  }

  // Cache-first for images / icons / fonts in /public
  if (url.pathname.match(/\.(png|jpg|jpeg|svg|ico|webp|gif|woff2?|ttf)$/)) {
    event.respondWith(cacheFirst(request))
    return
  }

  // Network-only for Supabase and other API calls (return error JSON if offline)
  if (url.hostname.includes('supabase') || url.pathname.startsWith('/api/')) {
    event.respondWith(
      fetch(request).catch(() =>
        new Response(JSON.stringify({ error: 'You are offline' }), {
          status: 503,
          headers: { 'Content-Type': 'application/json' },
        })
      )
    )
    return
  }

  // Network-first for HTML navigation; fall back to offline page
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request).catch(() =>
        caches.match(OFFLINE_URL).then(
          (r) => r ?? new Response('Offline', { status: 503 })
        )
      )
    )
    return
  }
})

// ─── Helpers ─────────────────────────────────────────────────────────────────
async function cacheFirst(request) {
  const cached = await caches.match(request)
  if (cached) return cached
  const response = await fetch(request)
  if (response.ok) {
    const cache = await caches.open(CACHE_NAME)
    cache.put(request, response.clone())
  }
  return response
}

// ─── Web Push ────────────────────────────────────────────────────────────────
self.addEventListener('push', (event) => {
  if (!event.data) return
  let payload = { title: 'PRV HOUSE', body: '', url: '/notifications' }
  try {
    payload = { ...payload, ...event.data.json() }
  } catch {
    payload.body = event.data.text()
  }
  event.waitUntil(
    self.registration.showNotification(payload.title, {
      body: payload.body,
      icon: '/icon-192.png',
      badge: '/icon-192.png',
      data: { url: payload.url },
      tag: payload.url, // collapse multiple pushes for the same target
    })
  )
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const url = (event.notification.data && event.notification.data.url) || '/notifications'
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          client.focus()
          if ('navigate' in client) client.navigate(url)
          return
        }
      }
      return self.clients.openWindow(url)
    })
  )
})
