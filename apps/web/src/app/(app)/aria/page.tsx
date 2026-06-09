import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { AriaPage } from '@/components/modules/aria/aria-page'

export const metadata: Metadata = { title: 'ARIA — Property Brain' }

export default async function AriaRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <AriaPage userId={user.id} />
    </div>
  )
}
