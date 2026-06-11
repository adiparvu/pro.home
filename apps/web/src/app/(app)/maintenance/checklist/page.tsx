import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { MoveChecklistPage } from '@/components/modules/maintenance/move-checklist-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Move-in / Move-out Checklist' }

export default async function ChecklistRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Move Checklists" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: checklists } = await (supabase as any)
    .from('move_checklists')
    .select('*')
    .eq('property_id', property.id)
    .order('created_at', { ascending: false })

  const checklistIds: string[] = (checklists ?? []).map((c: { id: string }) => c.id)

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: items } = checklistIds.length > 0
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    ? await (supabase as any)
        .from('move_checklist_items')
        .select('*')
        .in('checklist_id', checklistIds)
        .order('sort_order', { ascending: true })
    : { data: [] }

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <MoveChecklistPage
        property={property}
        userId={user.id}
        initialChecklists={checklists ?? []}
        initialItems={items ?? []}
      />
    </div>
  )
}
