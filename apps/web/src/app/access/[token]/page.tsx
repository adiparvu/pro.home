import { type Metadata } from 'next'
import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

interface Props { params: Promise<{ token: string }> }

export const metadata: Metadata = { title: 'Access — PRV HOUSE' }

function fmt(d: string | null) {
  if (!d) return null
  return new Date(d).toLocaleString('en', {
    day: 'numeric', month: 'long', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  })
}

export default async function AccessTokenPage({ params }: Props) {
  const { token } = await params
  const supabase = await createClient()

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: code } = await (supabase as any)
    .from('temp_access_codes')
    .select('*, properties(name, address_line1, city), profiles!created_by(display_name, full_name)')
    .eq('token', token)
    .maybeSingle()

  if (!code) notFound()

  const now = new Date()
  const isExpired = code.expires_at && new Date(code.expires_at) < now
  const isUsedUp = code.max_scans !== -1 && code.scanned_count >= code.max_scans

  const invalid = isExpired || isUsedUp

  // Increment scanned_count (fire-and-forget, best effort)
  if (!invalid) {
    const updates: Record<string, unknown> = {
      scanned_count: (code.scanned_count ?? 0) + 1,
    }
    if (!code.scanned_at) {
      updates.scanned_at = now.toISOString()
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any)
      .from('temp_access_codes')
      .update(updates)
      .eq('token', token)
  }

  const propertyName: string = code.properties?.name ?? 'Unknown property'
  const propertyAddress: string | null = code.properties
    ? [code.properties.address_line1, code.properties.city].filter(Boolean).join(', ')
    : null
  const createdBy: string = code.profiles?.display_name ?? code.profiles?.full_name ?? 'Unknown'
  const expiresAt = fmt(code.expires_at)

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
          <p style={{ margin: 0, fontSize: '10px', color: '#6b7280', letterSpacing: '0.1em', textTransform: 'uppercase' }}>Access Control</p>
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
          background: invalid ? '#7f1d1d' : '#14532d',
          padding: '20px 20px 16px',
          display: 'flex', alignItems: 'flex-start', gap: '14px',
        }}>
          <div style={{
            width: 48, height: 48, borderRadius: 12,
            background: 'rgba(255,255,255,0.15)',
            display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
          }}>
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,0.9)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              {invalid
                ? <><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></>
                : <><path d="M9 12l2 2 4-4"/><path d="M21 12c0 1.2-.504 2.294-1.32 3.08M3 12a9 9 0 1 0 18 0 9 9 0 0 0-18 0z"/></>
              }
            </svg>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <p style={{ margin: 0, fontSize: '18px', fontWeight: 700, color: 'white', lineHeight: 1.3 }}>
              {invalid ? 'Access Denied' : 'Access Granted'}
            </p>
            <p style={{ margin: '4px 0 0', fontSize: '13px', color: 'rgba(255,255,255,0.7)' }}>
              {isExpired ? 'This access code has expired.' : isUsedUp ? 'This access code has been used up.' : 'You have been granted access.'}
            </p>
          </div>
        </div>

        {/* Details */}
        {!invalid && (
          <>
            <div style={{ padding: '16px 20px 0' }}>
              {code.purpose && (
                <div style={{ display: 'flex', gap: '12px', padding: '10px 0', borderBottom: '1px solid #e5e7eb' }}>
                  <span style={{ minWidth: '130px', fontSize: '12px', color: '#6b7280', fontWeight: 500 }}>Purpose</span>
                  <span style={{ fontSize: '13px', color: '#111827', wordBreak: 'break-word', fontWeight: 600 }}>{code.purpose}</span>
                </div>
              )}
              <div style={{ display: 'flex', gap: '12px', padding: '10px 0', borderBottom: '1px solid #e5e7eb' }}>
                <span style={{ minWidth: '130px', fontSize: '12px', color: '#6b7280', fontWeight: 500 }}>Property</span>
                <div>
                  <span style={{ fontSize: '13px', color: '#111827', fontWeight: 600, display: 'block' }}>{propertyName}</span>
                  {propertyAddress && <span style={{ fontSize: '11px', color: '#9ca3af' }}>{propertyAddress}</span>}
                </div>
              </div>
              <div style={{ display: 'flex', gap: '12px', padding: '10px 0', borderBottom: '1px solid #e5e7eb' }}>
                <span style={{ minWidth: '130px', fontSize: '12px', color: '#6b7280', fontWeight: 500 }}>Authorized by</span>
                <span style={{ fontSize: '13px', color: '#111827' }}>{createdBy}</span>
              </div>
              {expiresAt && (
                <div style={{ display: 'flex', gap: '12px', padding: '10px 0', borderBottom: '1px solid #e5e7eb' }}>
                  <span style={{ minWidth: '130px', fontSize: '12px', color: '#6b7280', fontWeight: 500 }}>Valid until</span>
                  <span style={{ fontSize: '13px', color: '#111827' }}>{expiresAt}</span>
                </div>
              )}
              {code.notes && (
                <div style={{ display: 'flex', gap: '12px', padding: '10px 0', borderBottom: '1px solid #e5e7eb' }}>
                  <span style={{ minWidth: '130px', fontSize: '12px', color: '#6b7280', fontWeight: 500 }}>Notes</span>
                  <span style={{ fontSize: '13px', color: '#111827', wordBreak: 'break-word' }}>{code.notes}</span>
                </div>
              )}
            </div>
            <div style={{ padding: '16px 20px', background: '#f0fdf4' }}>
              <p style={{ margin: 0, fontSize: '12px', color: '#166534', fontWeight: 500 }}>
                ✓ Access verified at {now.toLocaleTimeString('en', { hour: '2-digit', minute: '2-digit' })}
              </p>
            </div>
          </>
        )}

        {invalid && (
          <div style={{ padding: '20px', textAlign: 'center' }}>
            <p style={{ margin: 0, fontSize: '13px', color: '#6b7280' }}>
              Please contact the property owner for a new access code.
            </p>
          </div>
        )}

        {/* Footer */}
        <div style={{
          background: '#f9fafb', borderTop: '1px solid #e5e7eb',
          padding: '12px 20px', textAlign: 'center',
        }}>
          <p style={{ margin: 0, fontSize: '11px', color: '#9ca3af' }}>
            PRV HOUSE · Secure Access System
          </p>
        </div>
      </div>
    </div>
  )
}
