import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { ScanPage } from '@/components/modules/inventory/scan-page'

export const metadata: Metadata = { title: 'M-SCAN™' }

export default async function InventoryScanPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  return <ScanPage propertyId={property?.id ?? null} />
}
