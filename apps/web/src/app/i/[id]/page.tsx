import { type Metadata } from 'next'
import { createClient } from '@/lib/supabase/server'

// Public "found item" page. Reached by scanning the QR printed on a physical
// item, so it must render for anyone — signed in or not. It reads only the
// `public_items` projection (publicly readable by policy), which the owner
// opts into per item via "Show on public QR page", so nothing private is
// exposed. Unknown / unpublished ids fall back to a friendly generic page
// instead of 404, because a finder should still learn the item is registered.

interface Props { params: Promise<{ id: string }> }

interface PublicItem {
  item_name: string | null
  owner_name: string | null
  owner_phone: string | null
  owner_address: string | null
  property_name: string | null
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

async function loadItem(id: string): Promise<PublicItem | null> {
  if (!UUID_RE.test(id)) return null
  const supabase = await createClient()
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data } = await (supabase as any)
    .from('public_items')
    .select('item_name, owner_name, owner_phone, owner_address, property_name')
    .eq('item_uuid', id)
    .maybeSingle()
  return (data as PublicItem) ?? null
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { id } = await params
  const item = await loadItem(id)
  return { title: item?.item_name ? `${item.item_name} · PRV House` : 'PRV House' }
}

const BrandMark = () => (
  <svg width="22" height="22" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
    <path fillRule="evenodd" fill="white" d="M18 10 h28 v80 h-28 Z M46 10 L68 10 Q90 10 90 33 Q90 56 68 56 L46 56 Z M46 26 L65 26 Q74 26 74 33 Q74 40 65 40 L46 40 Z" />
  </svg>
)

function Row({ label, value, href }: { label: string; value: string | null | undefined; href?: string }) {
  if (!value) return null
  return (
    <div style={{ display: 'flex', gap: 12, padding: '13px 16px', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
      <span style={{ minWidth: 64, fontSize: 12, color: 'rgba(255,255,255,0.4)', flexShrink: 0 }}>{label}</span>
      {href
        ? <a href={href} style={{ fontSize: 14, fontWeight: 500, color: '#5ab4ff', textDecoration: 'none', wordBreak: 'break-word' }}>{value}</a>
        : <span style={{ fontSize: 14, fontWeight: 500, color: '#f0f6ff', wordBreak: 'break-word' }}>{value}</span>}
    </div>
  )
}

export default async function PublicItemPage({ params }: Props) {
  const { id } = await params
  const item = await loadItem(id)

  const itemName = item?.item_name || 'PRV House Item'
  const hasContact = !!(item?.owner_name || item?.owner_phone || item?.owner_address)
  const message = item
    ? `Please return it to the owner${item.owner_name ? ` ${item.owner_name}` : ''}. Thank you for your honesty!`
    : 'This item belongs to a PRV House user. If you found or borrowed it, please try to return it to its owner.'

  return (
    <div style={{
      minHeight: '100dvh',
      background: '#0d1117',
      color: '#f0f6ff',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      padding: 20,
    }}>
      <div style={{
        background: 'rgba(255,255,255,0.07)',
        border: '1px solid rgba(255,255,255,0.12)',
        borderRadius: 24,
        padding: 32,
        maxWidth: 400,
        width: '100%',
      }}>
        {/* Brand */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 24 }}>
          <div style={{ width: 34, height: 34, borderRadius: 9, background: '#0D1420', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <BrandMark />
          </div>
          <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.35)', letterSpacing: 1, textTransform: 'uppercase' }}>PRV House</span>
        </div>

        <div style={{
          width: 64, height: 64, borderRadius: 18, background: 'rgba(255,140,0,0.15)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 16, fontSize: 28,
        }}>📦</div>

        <h1 style={{ fontSize: 26, fontWeight: 700, marginBottom: 4 }}>{itemName}</h1>
        {item?.property_name && (
          <p style={{ fontSize: 13, color: 'rgba(255,255,255,0.4)', marginBottom: 24 }}>{item.property_name}</p>
        )}

        <div style={{
          background: 'rgba(255,140,0,0.1)', border: '1px solid rgba(255,140,0,0.28)',
          borderRadius: 14, padding: '16px 18px', margin: '18px 0 22px',
        }}>
          <h2 style={{ fontSize: 14, fontWeight: 600, color: '#ffaa44', marginBottom: 6 }}>Found or Borrowed This Item?</h2>
          <p style={{ fontSize: 13, color: 'rgba(255,255,255,0.65)', lineHeight: 1.55 }}>{message}</p>
        </div>

        {hasContact && (
          <div style={{ background: 'rgba(255,255,255,0.04)', borderRadius: 14, overflow: 'hidden' }}>
            <Row label="Owner" value={item?.owner_name} />
            <Row label="Phone" value={item?.owner_phone} href={item?.owner_phone ? `tel:${item.owner_phone}` : undefined} />
            <Row label="Address" value={item?.owner_address} />
          </div>
        )}

        <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.18)', textAlign: 'center', marginTop: 28 }}>
          Powered by PRV House · Home Management
        </p>
      </div>
    </div>
  )
}
