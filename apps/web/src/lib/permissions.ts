import type { UserRole } from '@/lib/supabase/types'

/**
 * Centralized role → capability map. Every role-aware UI element (quick
 * actions, context menus, destructive buttons) must consult this map rather
 * than hard-coding role checks.
 */
export interface Capabilities {
  createTask: boolean
  createInventory: boolean
  createFinance: boolean
  createDocument: boolean
  createGarden: boolean
  createEnergyReading: boolean
  manageMembers: boolean
  manageProperty: boolean
  deleteRecords: boolean
}

const FULL: Capabilities = {
  createTask: true,
  createInventory: true,
  createFinance: true,
  createDocument: true,
  createGarden: true,
  createEnergyReading: true,
  manageMembers: true,
  manageProperty: true,
  deleteRecords: true,
}

const NONE: Capabilities = {
  createTask: false,
  createInventory: false,
  createFinance: false,
  createDocument: false,
  createGarden: false,
  createEnergyReading: false,
  manageMembers: false,
  manageProperty: false,
  deleteRecords: false,
}

const ROLE_CAPABILITIES: Record<UserRole, Capabilities> = {
  owner: FULL,
  partner: { ...FULL, manageProperty: false },
  family_adult: { ...FULL, manageMembers: false, manageProperty: false },
  family_teen: { ...NONE, createTask: true, createGarden: true },
  family_child: NONE,
  family_elderly: { ...NONE, createTask: true },
  tenant: { ...NONE, createTask: true, createDocument: true, createEnergyReading: true },
  guest: NONE,
  service_provider: { ...NONE, createTask: true },
}

export function getCapabilities(role: UserRole | null | undefined): Capabilities {
  if (!role) return NONE
  return ROLE_CAPABILITIES[role] ?? NONE
}
