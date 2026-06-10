import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { Property } from '@/lib/supabase/types'

interface PropertyState {
  activePropertyId: string | null
  setActivePropertyId: (id: string | null) => void
  recentPropertyIds: string[]
  addRecentProperty: (id: string) => void
}

export const usePropertyStore = create<PropertyState>()(
  persist(
    (set) => ({
      activePropertyId: null,
      setActivePropertyId: (id) => set({ activePropertyId: id }),
      recentPropertyIds: [],
      addRecentProperty: (id) =>
        set((state) => ({
          activePropertyId: id,
          recentPropertyIds: [id, ...state.recentPropertyIds.filter((p) => p !== id)].slice(0, 5),
        })),
    }),
    {
      name: 'prv-property',
    }
  )
)
