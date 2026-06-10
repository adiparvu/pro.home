import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { MoreMenu } from '@/components/modules/more/more-menu'

export const metadata: Metadata = { title: 'More' }

export default async function MorePage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <MoreMenu />
    </div>
  )
}
