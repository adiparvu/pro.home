import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import PostalMime from 'https://esm.sh/postal-mime@2.4.4'

// ─── email-inbound ────────────────────────────────────────────────────────────
// Receives a forwarded shipping email (via an inbound-email provider that POSTs
// a normalized JSON body), figures out which property it's for from the
// forwarding address token, extracts the tracking number(s), and folds them
// into ONE delivery. An email describes a single parcel even when it quotes
// several references (order number, courier AWB, carrier code), so the best
// reference becomes the tracking number and the rest ride along as aliases.
// Successive emails about the same order — retailer confirmation, then courier
// registration — share at least one reference, so they merge into the existing
// row instead of spawning a duplicate card.
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
    // Phone-shaped runs must never become references: a recipient's mobile in
    // the delivery-address block sits right next to shipping words in EVERY
    // email from that store, and a shared bogus reference would merge two
    // different orders into one card (the false-merge vector).
    if (/^0\d{9}$/.test(n)) continue // national mobile/landline (leading 0)
    const at = m.index ?? 0
    const left = clean.slice(Math.max(0, at - 24), at)
    if (/(?:tel|phone|mobil|contact|fax|\+\d{1,3})\s*[:.]?\s*$/i.test(left)) continue
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

// One parcel, many spellings: retailers quote a long order number, couriers a
// shorter AWB or a carrier-format code. Rank the shapes so the most trackable
// reference becomes the primary tracking number and the rest become aliases.
type RefKind = 'carrier' | 'awb' | 'order'
const REF_RANK: Record<RefKind, number> = { carrier: 0, awb: 1, order: 2 }

function classifyReference(n: string): RefKind {
  if (/^1Z[0-9A-Z]{16}$/.test(n) || /^[A-Z]{2}\d{9}[A-Z]{2}$/.test(n)) return 'carrier'
  if (/^\d{10,14}$/.test(n)) return 'awb'
  return 'order' // 15–22 digit runs (extraction never yields anything shorter)
}

// First carrier-format code, else first AWB, else first order number. Strict
// "<" keeps the pick stable within a rank, so re-processing the same email
// lands on the same primary.
function bestReference(refs: string[]): string {
  let best = refs[0]
  for (const r of refs) {
    if (REF_RANK[classifyReference(r)] < REF_RANK[classifyReference(best)]) best = r
  }
  return best
}

// Merchant display value from the sender: the From header's display name when
// it carries one ("eMAG <x@emag.ro>"), else the second-level domain
// capitalized ("emag.ro" -> "Emag"). Callers pass courier senders through
// courierFromSender instead — there the carrier field already holds the label.
function merchantFromSender(from: string, parsedName: string): string | null {
  const display = (parsedName || from.match(/^\s*"?([^"<]+?)"?\s*</)?.[1] || '').trim()
  if (display) return display.slice(0, 80)
  const address = from.match(/<([^>]+)>/)?.[1] ?? from
  const domain = (address.split('@')[1] ?? '').toLowerCase().replace(/[^a-z0-9.-]/g, '')
  const parts = domain.split('.').filter(Boolean)
  if (parts.length < 2) return null
  const label = parts[parts.length - 2]
  return label.charAt(0).toUpperCase() + label.slice(1)
}

// Register with Ship24 (best-effort; auto-detects courier from the number).
// A null return never blocks the write — the webhook can still match by number.
async function registerTracker(apiKey: string | undefined, trackingNumber: string): Promise<string | null> {
  if (!apiKey) return null
  try {
    const res = await fetch(`${SHIP24_BASE}/trackers`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ trackingNumber }),
    })
    if (res.ok) return (await res.json())?.data?.tracker?.trackerId ?? null
  } catch { /* leave null */ }
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
  let fromName = ''

  if (body?.raw) {
    try {
      const parsed = await PostalMime.parse(String(body.raw))
      subject = subject || parsed?.subject || ''
      textPart = textPart || parsed?.text || ''
      htmlPart = htmlPart || parsed?.html || ''
      if (!from) from = parsed?.from?.address ?? ''
      if (!fromName) fromName = parsed?.from?.name ?? ''
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
  if (numbers.length === 0) return json({ ok: true, created: 0, merged: 0, note: 'no tracking number found' }, 200)

  // Campaign mail is rejected outright unless it came from a known courier
  // domain or carries a carrier-format number (couriers put unsubscribe
  // footers in genuine notifications too, so those two signals win).
  const hasCarrierFormat = numbers.some((n) => /^1Z[0-9A-Z]{16}$|^[A-Z]{2}\d{9}[A-Z]{2}$/.test(n))
  if (!carrier && !hasCarrierFormat && MARKETING_RE.test(haystack)) {
    return json({ ok: true, created: 0, merged: 0, note: 'rejected: bulk/marketing email' }, 200)
  }

  const description = (subject || 'Delivery').slice(0, 120)
  // Known courier sender: the parcel's shop is unknown here, so merchant stays
  // null and only the carrier label is recorded.
  const merchant = carrier ? null : merchantFromSender(from, fromName)
  const emailStamp = { at: new Date().toISOString(), from, subject }
  let created = 0
  let merged = 0

  // Merge candidates: recent parcels on this property. Matching runs in JS
  // because a reference may sit in tracking_number OR inside the aliases json
  // array, and the window (100 rows / 90 days) keeps the scan cheap.
  const CANDIDATE_COLUMNS = 'id, tracking_number, aliases, merchant, carrier, tracker_id, source_emails, created_at'
  const since = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString()
  const { data: candidates, error: candidatesError } = await admin
    .from('packages')
    .select(CANDIDATE_COLUMNS)
    .eq('property_id', propertyId)
    .gte('created_at', since)
    .order('created_at', { ascending: false })
    .limit(100)
  // A failed scan must NOT fall through to the insert branch — that forks a
  // duplicate card. A 5xx makes the inbound provider retry the email instead.
  if (candidatesError) return json({ error: 'db error' }, 500)

  const matches = (candidates ?? []).filter((c) => {
    const refs = new Set<string>(
      [c.tracking_number, ...(Array.isArray(c.aliases) ? c.aliases : [])].filter(Boolean),
    )
    return numbers.some((n) => refs.has(n))
  })

  // Merge into the OLDEST matching row — that is the card the user already
  // sees; writing into a newer duplicate would fork the delivery's history.
  // Candidates arrive newest-first, so the oldest match is the last one.
  let target = matches.length > 0 ? matches[matches.length - 1] : null

  // The window is a cost cap, not a truth boundary: a re-forwarded email
  // about an older parcel (or a property with >100 recent packages) must
  // still find its row. One cheap exact probe on the would-be primary
  // restores the old code's unbounded exact-match guarantee.
  if (!target) {
    const { data: exact, error: exactError } = await admin
      .from('packages')
      .select(CANDIDATE_COLUMNS)
      .eq('property_id', propertyId)
      .eq('tracking_number', bestReference(numbers))
      .maybeSingle()
    if (exactError) return json({ error: 'db error' }, 500)
    if (exact) target = exact
  }

  if (target) {

    // Union of everything known about this parcel, in stable order: the row's
    // current primary, its aliases, then this email's references.
    const union: string[] = []
    for (const r of [target.tracking_number, ...(Array.isArray(target.aliases) ? target.aliases : []), ...numbers]) {
      if (r && !union.includes(r)) union.push(r)
    }
    const primary = bestReference(union)

    // Description is NOT overwritten on merge — the first email named the card.
    const patch: Record<string, unknown> = {
      tracking_number: primary,
      aliases: union.filter((r) => r !== primary),
      merchant: target.merchant ?? merchant,
      carrier: target.carrier ?? carrier,
      source_emails: [
        ...(Array.isArray(target.source_emails) ? target.source_emails : []),
        emailStamp,
      ].slice(-10),
      last_synced_at: new Date().toISOString(),
    }

    // A better reference just arrived (e.g. the courier's real AWB after an
    // order-number-only confirmation) — point live tracking at it. Only when
    // the registration actually succeeds: overwriting a working tracker_id
    // with null would silence the webhook's stable-id match and turn live
    // tracking dark instead of degrading to the old tracker.
    if (primary !== target.tracking_number) {
      const fresh = await registerTracker(apiKey, primary)
      if (fresh) {
        patch.tracker_id = fresh
        patch.live_status = 'pending'
        patch.tracking_enabled = true
      }
    }

    // A lost email is unrecoverable; a 5xx makes the provider redeliver it.
    const { error } = await admin.from('packages').update(patch).eq('id', target.id)
    if (error) return json({ error: 'db error' }, 500)
    merged += 1
  } else {
    // One email = at most one parcel: the best reference is the tracking
    // number, every other extracted number becomes an alias for later merges.
    const primary = bestReference(numbers)
    const trackerId = await registerTracker(apiKey, primary)

    const { error } = await admin.from('packages').insert({
      property_id: propertyId,
      description,
      status: 'expected',
      tracking_number: primary,
      aliases: numbers.filter((n) => n !== primary),
      merchant,
      carrier,
      source_emails: [emailStamp],
      tracker_id: trackerId,
      live_status: 'pending',
      tracking_enabled: true,
      last_synced_at: new Date().toISOString(),
    })
    if (error) return json({ error: 'db error' }, 500)
    created += 1
  }

  return json({ ok: true, created, merged }, 200)
})

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}
