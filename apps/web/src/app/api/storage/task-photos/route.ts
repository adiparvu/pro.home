import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function POST(req: NextRequest) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const form = await req.formData()
  const file = form.get('file') as File | null
  const taskId = form.get('taskId') as string | null
  const slot = (form.get('slot') as string) ?? 'before' // 'before' | 'after'

  if (!file || !taskId) return NextResponse.json({ error: 'Missing file or taskId' }, { status: 400 })
  if (file.size > 8 * 1024 * 1024) return NextResponse.json({ error: 'File too large (max 8 MB)' }, { status: 400 })

  const ext = file.name.split('.').pop() ?? 'jpg'
  const path = `${user.id}/${taskId}/${slot}-${Date.now()}.${ext}`
  const bytes = await file.arrayBuffer()

  const { error } = await supabase.storage.from('task-photos').upload(path, bytes, {
    contentType: file.type,
    upsert: false,
  })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  const { data: { publicUrl } } = supabase.storage.from('task-photos').getPublicUrl(path)

  // Append to the task's photo array
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: task } = await (supabase as any).from('maintenance_tasks').select(`${slot}_photo_urls`).eq('id', taskId).single() as {
    data: { before_photo_urls?: string[] | null; after_photo_urls?: string[] | null } | null
  }
  const field = slot === 'after' ? 'after_photo_urls' : 'before_photo_urls'
  const existing: string[] = (task?.[field] ?? []) as string[]
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (supabase as any).from('maintenance_tasks').update({ [field]: [...existing, publicUrl] }).eq('id', taskId)

  return NextResponse.json({ url: publicUrl })
}
