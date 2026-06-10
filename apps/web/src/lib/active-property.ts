import { cookies } from 'next/headers'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Property } from '@/lib/supabase/types'

export const ACTIVE_PROPERTY_COOKIE = 'prv-active-property'

/**
 * Resolves the user's active property: the one selected via the property
 * switcher (persisted in a cookie), falling back to the most recently
 * created membership. Every module page must use this instead of querying
 * the first membership directly, so the switcher applies app-wide.
 */
export async function getActiveProperty(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: SupabaseClient<any, any, any>,
  userId: string
): Promise<Property | null> {
  const [{ data: properties }, cookieStore] = await Promise.all([
    supabase
      .from('properties')
      .select('*, property_members!inner(role, status)')
      .eq('property_members.user_id', userId)
      .eq('property_members.status', 'active')
      .eq('is_active', true)
      .order('created_at', { ascending: false }) as unknown as Promise<{ data: Property[] | null }>,
    cookies(),
  ])

  if (!properties || properties.length === 0) return null

  const preferred = cookieStore.get(ACTIVE_PROPERTY_COOKIE)?.value
  return properties.find((p) => p.id === preferred) ?? properties[0]!
}

/** All active properties for the switcher UI. */
export async function getMemberProperties(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: SupabaseClient<any, any, any>,
  userId: string
): Promise<Property[]> {
  const { data } = await supabase
    .from('properties')
    .select('*, property_members!inner(role, status)')
    .eq('property_members.user_id', userId)
    .eq('property_members.status', 'active')
    .eq('is_active', true)
    .order('created_at', { ascending: false }) as unknown as { data: Property[] | null }
  return data ?? []
}
