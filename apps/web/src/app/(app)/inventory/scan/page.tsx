import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { Property } from '@/lib/supabase/types'
import { ScanPage } from '@/components/modules/inventory/scan-page'

export const metadata: Metadata = { title: 'M-SCAN™' }

export default async function InventoryScanPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: property } = await supabase
    .from('properties')
    .select('id, name, *, property_members!inner(role, status)')
    .eq('property_members.user_id', user.id)
    .eq('property_members.status', 'active')
    .eq('is_active', true)
    .order('created_at', { ascending: false })
    .limit(1)
    .single() as { data: Property | null; error: unknown }

  return <ScanPage propertyId={property?.id ?? null} />
}
