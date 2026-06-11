import { type Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveProperty } from '@/lib/active-property'
import { ProjectsPage } from '@/components/modules/projects/projects-page'
import { PageHeader } from '@/components/layout/page-header'
import { NoPropertyState } from '@/components/modules/dashboard/no-property-state'

export const metadata: Metadata = { title: 'Projects' }

export default async function ProjectsRoute() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const property = await getActiveProperty(supabase, user.id)

  if (!property) {
    return (
      <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
        <PageHeader title="Projects" />
        <NoPropertyState />
      </div>
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: projects } = await (supabase as any)
    .from('projects')
    .select('*, rooms(name)')
    .eq('property_id', property.id)
    .order('created_at', { ascending: false })

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: taskCounts } = await (supabase as any)
    .from('maintenance_tasks')
    .select('project_id, status')
    .eq('property_id', property.id)
    .not('project_id', 'is', null)

  return (
    <div className="flex flex-1 flex-col pb-[116px] md:pb-0">
      <ProjectsPage
        property={property}
        initialProjects={projects ?? []}
        taskCounts={taskCounts ?? []}
      />
    </div>
  )
}
