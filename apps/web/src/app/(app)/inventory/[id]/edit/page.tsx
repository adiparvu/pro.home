import { type Metadata } from 'next'
import { redirect, notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { InventoryItem } from '@/lib/supabase/types'
import { EditInventoryItemForm } from '@/components/modules/inventory/edit-inventory-item-form'
import { ChevronLeft } from 'lucide-react'
import Link from 'next/link'

export const metadata: Metadata = { title: 'Edit Item' }

interface Props { params: Promise<{ id: string }> }

export default async function EditInventoryItemPage({ params }: Props) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: item } = await supabase
    .from('inventory_items')
    .select('*')
    .eq('id', id)
    .single() as { data: InventoryItem | null; error: unknown }

  if (!item) notFound()

  return (
    <div className="flex flex-1 flex-col pb-[88px] md:pb-0">
      <header className="glass-opaque sticky top-0 z-20 border-b border-border/50 px-4 py-4 md:px-6">
        <div className="flex items-center gap-3">
          <Link
            href={`/inventory/${id}`}
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg glass-light text-muted-foreground hover:text-foreground transition-colors focus-ring"
          >
            <ChevronLeft className="h-4 w-4" />
          </Link>
          <h1 className="text-lg font-bold text-foreground">Edit Item</h1>
        </div>
      </header>
      <div className="px-4 py-4 md:px-6 md:py-6">
        <EditInventoryItemForm item={item} />
      </div>
    </div>
  )
}
