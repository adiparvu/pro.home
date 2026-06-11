import { type Metadata } from 'next'
import { createClient } from '@/lib/supabase/server'
import { TenantPortalPublicPage } from './tenant-portal-public-page'

export const metadata: Metadata = { title: 'Tenant Portal' }

interface Props { params: Promise<{ token: string }> }

export default async function TenantPortalTokenPage({ params }: Props) {
  const { token } = await params
  const supabase = await createClient()

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: portal } = await (supabase as any)
    .from('tenant_portals')
    .select('id, property_id, label, active, properties(name)')
    .eq('token', token)
    .single()

  if (!portal || !portal.active) {
    return (
      <div style={{
        minHeight: '100dvh',
        background: '#f9fafb',
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '24px 16px',
      }}>
        <div style={{
          width: '100%',
          maxWidth: '480px',
          background: 'white',
          borderRadius: '16px',
          border: '1px solid #e5e7eb',
          padding: '32px 24px',
          textAlign: 'center',
          boxShadow: '0 1px 3px rgba(0,0,0,0.06)',
        }}>
          <p style={{ fontSize: '16px', fontWeight: 600, color: '#111827', margin: '0 0 8px' }}>Portal not found or inactive</p>
          <p style={{ fontSize: '13px', color: '#6b7280', margin: 0 }}>Please contact your property manager for a valid link.</p>
        </div>
      </div>
    )
  }

  const propertyName: string = portal.properties?.name ?? 'Your Property'

  return (
    <TenantPortalPublicPage
      portalId={portal.id as string}
      propertyId={portal.property_id as string}
      portalLabel={portal.label as string}
      propertyName={propertyName}
    />
  )
}
