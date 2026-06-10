import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { MarketplacePage } from '@/components/modules/marketplace/marketplace-page'

export const metadata: Metadata = { title: 'Marketplace' }

export default async function MarketplaceRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <MarketplacePage />
    </div>
  )
}
