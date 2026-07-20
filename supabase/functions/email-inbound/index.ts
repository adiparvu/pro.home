import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import PostalMime from 'https://esm.sh/postal-mime@2.4.4'

// ─── email-inbound ────────────────────────────────────────────────────────────
// Receives a forwarded shipping email (via an inbound-email provider that POSTs
// a normalized JSON body), figures out which property it's for from the
// forwarding address token, extracts the tracking number(s), creates the
// delivery, and registers it for live tracking with Ship24.
//
// Security: the provider is configured to call this URL with a shared secret in
// the query string (?secret=…) matching EMAIL_INBOUND_SECRET.
//
// Required secrets (no-op 503 until set):
//   EMAIL_INBOUND_SECRET                       – shared secret in the endpoint URL
//   SHIP24_API_KEY                             – Ship24 API key (for auto-registration)
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY   – provided by the platform
// ──────────────────────────────────────────────────────────────────────────────

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SHIP24_BASE = 'https://api.ship24.com/public/v1'

// Sender-domain -> human courier label (Ship24 still auto-detects from the
// number; this is only for a nicer display value).
const COURIER_BY_DOMAIN: Record<string, string> = {
  'dhl': 'DHL', 'sameday': 'Sameday', 'fancourier': 'Fan Courier', 'fan-courier': 'Fan Courier',
  'cargus': 'Cargus', 'urgentcargus': 'Cargus', 'dpd': 'DPD', 'gls': 'GLS', 'ups': 'UPS',
  'fedex': 'FedEx', 'bpost': 'bpost', 'postnl': 'PostNL', 'gls-group': 'GLS',
}

function stripHtml(html: string): string {
  return html.replace(/<style[\s\S]*?<\/style>/gi, ' ')
             .replace(/<script[\s\S]*?<\/script>/gi, ' ')
             .replace(/<[^>]+>/g, ' ')
             .replace(/&nbsp;/g, ' ')
             .replace(/\s+/g, ' ')
}

// Bulk-mail fingerprints. A real courier notification from a known domain (or
// one carrying a carrier-format tracking number) still passes; anything else
// that smells like a campaign is dropped before extraction.
const MARKETING_RE = new RegExp(
  [
    'unsubscribe', 'dezabon', 'd[ée]sabonn', 'uitschrijven', 'afmelden', 'abmelden',
    'newsletter', 'view (this email )?in (your )?browser',
    'probl[èe]mes? de visualisation', 'problemen met het bekijken',
    'special offer', 'ofert[ăa] special', 'voucher', 'gift ?card', 'sweepstake',
    'win\\b.{0,40}\\bprij', 'c[âa][șs]tig[ăa]',
  ].join('|'), 'i')

// Words that mean "a parcel is moving" — used as PROXIMITY context, never as a
// whole-email pass. Deliberately excludes loose matches like "sent" (which
// hides inside "consent"/"present" and passed a Coca-Cola campaign through).
const SHIPPING_CONTEXT_RE =
  /awb|tracking|track(?:ing)?\s*(?:no|number|num[ăa]r)|num[ăa]r\s+de\s+urm[ăa]rire|urm[ăa]re[șs]te|colet|expedi(?:at|ere|tion)|shipment|shipping|liver[ăa]|livrar|livrat|delivery|deliver(?:ed|y)|parcel|pachetul|trimis[ăa]?\s+(?:coletul|comanda)|comanda\s+(?:a fost )?expediat/i

// Extract candidate tracking numbers, fail-closed:
//  - carrier-format patterns (UPS 1Z…, UPU S10) are always accepted;
//  - generic 10–22 digit runs count ONLY when shipping context sits within
//    ±120 characters of the number (a keyword anywhere in a marketing email
//    used to qualify every campaign id in it);
//  - URLs are stripped first — their long numeric ids were the main source of
//    fake parcels.
function extractTrackingNumbers(text: string): string[] {
  const clean = text.replace(/https?:\/\/\S+/gi, ' ')
  const found = new Set<string>()

  for (const m of clean.matchAll(/\b1Z[0-9A-Z]{16}\b/g)) found.add(m[0])          // UPS
  for (const m of clean.matchAll(/\b[A-Z]{2}\d{9}[A-Z]{2}\b/g)) found.add(m[0])   // UPU S10 (DHL, posts)

  for (const m of clean.matchAll(/\b\d{10,22}\b/g)) {
    const n = m[0]
    if (/^(\d)\1+$/.test(n)) continue // all-same-digit
    const at = m.index ?? 0
    const context = clean.slice(Math.max(0, at - 120), at + n.length + 120)
    if (SHIPPING_CONTEXT_RE.test(context)) found.add(n)
  }

  return Array.from(found).slice(0, 5)
}

function courierFromSender(from: string): string | null {
  const domain = (from.split('@')[1] ?? '').toLowerCase()
  for (const key of Object.keys(COURIER_BY_DOMAIN)) {
    if (domain.includes(key)) return COURIER_BY_DOMAIN[key]
  }
  return null
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  const secret = Deno.env.get('EMAIL_INBOUND_SECRET')
  const apiKey = Deno.env.get('SHIP24_API_KEY')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!secret || !supabaseUrl || !serviceKey) {
    return json({ error: 'inbound not configured' }, 503)
  }

  const url = new URL(req.url)
  if ((url.searchParams.get('secret') ?? '').trim() !== secret.trim()) {
    return json({ error: 'unauthorized' }, 401)
  }

  let body: any
  try { body = await req.json() } catch { return json({ error: 'bad request' }, 400) }

  // Normalize across providers. A Cloudflare Email Worker sends the raw RFC822
  // message (dependency-free on its side); everything else sends parsed fields.
  let to = String(body?.to ?? body?.recipient ?? body?.To ?? '')
  let from = String(body?.from ?? body?.sender ?? body?.From ?? '')
  let subject = String(body?.subject ?? body?.Subject ?? '')
  let textPart = String(body?.text ?? body?.plain ?? body?.TextBody ?? '')
  let htmlPart = String(body?.html ?? body?.HtmlBody ?? '')

  if (body?.raw) {
    try {
      const parsed = await PostalMime.parse(String(body.raw))
      subject = subject || parsed?.subject || ''
      textPart = textPart || parsed?.text || ''
      htmlPart = htmlPart || parsed?.html || ''
      if (!from) from = parsed?.from?.address ?? ''
      if (!to) to = (parsed?.to?.[0]?.address) ?? ''
    } catch { /* fall back to whatever fields were provided */ }
  }

  // Routing token = local-part of the forwarding address, minus any +suffix.
  const localPart = (to.match(/([^<@\s]+)@/)?.[1] ?? to.split('@')[0] ?? '').split('+')[0].trim()
  if (!localPart) return json({ ok: true, ignored: 'no recipient' }, 200)

  const admin = createClient(supabaseUrl, serviceKey)
  const { data: inbox } = await admin
    .from('parcel_inbox').select('property_id, active').eq('token', localPart).maybeSingle()
  if (!inbox || inbox.active === false) return json({ ok: true, ignored: 'unknown inbox' }, 200)

  const propertyId = inbox.property_id
  const haystack = `${subject}\n${textPart}\n${stripHtml(htmlPart)}`
  const carrier = courierFromSender(from)

  const numbers = extractTrackingNumbers(haystack)
  if (numbers.length === 0) return json({ ok: true, created: 0, note: 'no tracking number found' }, 200)

  // Campaign mail is rejected outright unless it came from a known courier
  // domain or carries a carrier-format number (couriers put unsubscribe
  // footers in genuine notifications too, so those two signals win).
  const hasCarrierFormat = numbers.some((n) => /^1Z[0-9A-Z]{16}$|^[A-Z]{2}\d{9}[A-Z]{2}$/.test(n))
  if (!carrier && !hasCarrierFormat && MARKETING_RE.test(haystack)) {
    return json({ ok: true, created: 0, note: 'rejected: bulk/marketing email' }, 200)
  }
  const description = (subject || 'Delivery').slice(0, 120)
  let created = 0

  for (const trackingNumber of numbers) {
    // Skip if this property already has this parcel.
    const { data: existing } = await admin
      .from('packages').select('id')
      .eq('property_id', propertyId).eq('tracking_number', trackingNumber).maybeSingle()
    if (existing) continue

    // Register with Ship24 (best-effort; auto-detects courier from the number).
    let trackerId: string | null = null
    if (apiKey) {
      try {
        const res = await fetch(`${SHIP24_BASE}/trackers`, {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ trackingNumber }),
        })
        if (res.ok) trackerId = (await res.json())?.data?.tracker?.trackerId ?? null
      } catch { /* leave trackerId null; webhook can still match by number */ }
    }

    const { error } = await admin.from('packages').insert({
      property_id: propertyId,
      description,
      status: 'expected',
      tracking_number: trackingNumber,
      carrier,
      tracker_id: trackerId,
      live_status: 'pending',
      tracking_enabled: true,
      last_synced_at: new Date().toISOString(),
    })
    if (!error) created += 1
  }

  return json({ ok: true, created }, 200)
})

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}
