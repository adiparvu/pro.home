import { type Metadata } from 'next'
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

interface Props { params: Promise<{ id: string }> }

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { id } = await params
  const supabase = await createClient()
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data } = await (supabase as any).from('inventory_items').select('name, brand').eq('id', id).maybeSingle()
  return { title: data ? `${data.name}${data.brand ? ` · ${data.brand}` : ''}` : 'Item' }
}

function fmt(d: string | null) {
  if (!d) return null
  return new Date(d).toLocaleDateString('en', { day: 'numeric', month: 'long', year: 'numeric' })
}

function Row({ label, value }: { label: string; value: string | null | undefined }) {
  if (!value) return null
  return (
    <div style={{ display: 'flex', gap: '12px', padding: '10px 0', borderBottom: '1px solid #e5e7eb' }}>
      <span style={{ minWidth: '140px', fontSize: '12px', color: '#6b7280', fontWeight: 500 }}>{label}</span>
      <span style={{ fontSize: '13px', color: '#111827', wordBreak: 'break-word' }}>{value}</span>
    </div>
  )
}

export default async function PublicItemPage({ params }: Props) {
  const { id } = await params
  const supabase = await createClient()

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: item } = await (supabase as any)
    .from('inventory_items')
    .select('id, name, brand, model, category, serial_number, barcode, condition, purchase_date, warranty_expires, warranty_provider, room_id, tags, created_at')
    .eq('id', id)
    .maybeSingle()

  if (!item) notFound()

  // Fetch room, property, and owner in parallel
  const [roomResult, propertyResult, ownerResult] = await Promise.all([
    item.room_id
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ? (supabase as any).from('rooms').select('name').eq('id', item.room_id).maybeSingle()
      : Promise.resolve({ data: null }),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any).from('properties').select('name, address').eq('id', item.property_id).maybeSingle(),
    // Owner = active member with role 'owner' or 'partner', joined with their profile
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (supabase as any)
      .from('property_members')
      .select('role, profiles(full_name, display_name)')
      .eq('property_id', item.property_id)
      .eq('role', 'owner')
      .eq('status', 'active')
      .maybeSingle(),
  ])

  const roomName: string | null = roomResult.data?.name ?? null
  const propertyAddress: string | null = propertyResult.data?.address ?? null
  const propertyDisplayName: string | null = propertyResult.data?.name ?? null
  const ownerName: string | null = ownerResult.data?.profiles?.display_name ?? ownerResult.data?.profiles?.full_name ?? null

  const registeredOn = fmt(item.created_at)
  const purchaseDate = fmt(item.purchase_date)
  const warrantyExpiry = fmt(item.warranty_expires)
  const tags: string[] = Array.isArray(item.tags) ? item.tags : []

  return (
    <div style={{
      minHeight: '100dvh',
      background: '#f9fafb',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      padding: '24px 16px 48px',
    }}>
      {/* Brand header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '24px' }}>
        <div style={{
          width: 40, height: 40, borderRadius: 10,
          background: '#0D1420', display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <svg width="22" height="22" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
            <path fillRule="evenodd" fill="white" d="M18 10 h28 v80 h-28 Z M46 10 L68 10 Q90 10 90 33 Q90 56 68 56 L46 56 Z M46 26 L65 26 Q74 26 74 33 Q74 40 65 40 L46 40 Z"/>
          </svg>
        </div>
        <div>
          <p style={{ margin: 0, fontSize: '13px', fontWeight: 700, color: '#0D1420', letterSpacing: '0.05em' }}>PRV HOUSE</p>
          <p style={{ margin: 0, fontSize: '10px', color: '#6b7280', letterSpacing: '0.1em', textTransform: 'uppercase' }}>Item Registry</p>
        </div>
      </div>

      {/* Card */}
      <div style={{
        width: '100%', maxWidth: '480px',
        background: 'white',
        borderRadius: '16px',
        border: '1px solid #e5e7eb',
        overflow: 'hidden',
        boxShadow: '0 1px 3px rgba(0,0,0,0.06), 0 4px 16px rgba(0,0,0,0.06)',
      }}>
        {/* Card header */}
        <div style={{
          background: '#0D1420', padding: '20px 20px 16px',
          display: 'flex', alignItems: 'flex-start', gap: '14px',
        }}>
          <div style={{
            width: 48, height: 48, borderRadius: 12, background: 'rgba(255,255,255,0.1)',
            display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
          }}>
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,0.7)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/>
              <path d="M14 14h3v3M17 17v4h4M14 21h3"/>
            </svg>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <p style={{ margin: 0, fontSize: '18px', fontWeight: 700, color: 'white', lineHeight: 1.3 }}>{item.name}</p>
            {(item.brand || item.model) && (
              <p style={{ margin: '2px 0 0', fontSize: '13px', color: 'rgba(255,255,255,0.6)' }}>
                {[item.brand, item.model].filter(Boolean).join(' · ')}
              </p>
            )}
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', marginTop: '8px' }}>
              {item.category && (
                <span style={{
                  background: 'rgba(255,255,255,0.12)', color: 'rgba(255,255,255,0.85)',
                  fontSize: '10px', padding: '2px 8px', borderRadius: '99px', textTransform: 'capitalize',
                }}>
                  {item.category}
                </span>
              )}
              {propertyDisplayName && (
                <span style={{
                  background: 'rgba(255,255,255,0.08)', color: 'rgba(255,255,255,0.7)',
                  fontSize: '10px', padding: '2px 8px', borderRadius: '99px',
                }}>
                  {propertyDisplayName}
                </span>
              )}
            </div>
          </div>
        </div>

        {/* Property & owner info */}
        {(propertyDisplayName || ownerName || propertyAddress) && (
          <div style={{
            background: '#f9fafb', borderBottom: '1px solid #e5e7eb',
            padding: '10px 20px', display: 'flex', flexDirection: 'column', gap: '4px',
          }}>
            {propertyDisplayName && (
              <p style={{ margin: 0, fontSize: '12px', color: '#374151' }}>
                <span style={{ color: '#6b7280' }}>Property: </span>
                <span style={{ fontWeight: 600 }}>{propertyDisplayName}</span>
              </p>
            )}
            {ownerName && (
              <p style={{ margin: 0, fontSize: '12px', color: '#374151' }}>
                <span style={{ color: '#6b7280' }}>Owner: </span>
                <span style={{ fontWeight: 600 }}>{ownerName}</span>
              </p>
            )}
            {propertyAddress && (
              <p style={{ margin: 0, fontSize: '11px', color: '#9ca3af' }}>{propertyAddress}</p>
            )}
          </div>
        )}

        {/* Details */}
        <div style={{ padding: '4px 20px 16px' }}>
          <Row label="Serial number" value={item.serial_number} />
          <Row label="Barcode" value={item.barcode} />
          <Row label="Room" value={roomName} />
          <Row label="Condition" value={item.condition ? item.condition.replace(/_/g, ' ') : null} />
          <Row label="Registered on" value={registeredOn} />
          <Row label="Purchase date" value={purchaseDate} />
          <Row label="Warranty expires" value={warrantyExpiry} />
          <Row label="Warranty provider" value={item.warranty_provider} />
          {tags.length > 0 && (
            <div style={{ display: 'flex', gap: '12px', padding: '10px 0', borderBottom: '1px solid #e5e7eb' }}>
              <span style={{ minWidth: '140px', fontSize: '12px', color: '#6b7280', fontWeight: 500 }}>Tags</span>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px' }}>
                {tags.map((tag: string) => (
                  <span key={tag} style={{
                    background: '#f3f4f6', color: '#374151',
                    fontSize: '11px', padding: '2px 8px', borderRadius: '99px',
                  }}>{tag}</span>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div style={{
          background: '#f9fafb', borderTop: '1px solid #e5e7eb',
          padding: '12px 20px', textAlign: 'center',
        }}>
          <p style={{ margin: 0, fontSize: '11px', color: '#9ca3af' }}>
            PRV HOUSE · Property ID: {id.slice(0, 8).toUpperCase()}
          </p>
        </div>
      </div>
    </div>
  )
}
