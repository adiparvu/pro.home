export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

// ─── Enum Types ──────────────────────────────────────────────────────────────

export type UserRole =
  | 'owner'
  | 'partner'
  | 'family_adult'
  | 'family_teen'
  | 'family_child'
  | 'family_elderly'
  | 'tenant'
  | 'guest'
  | 'service_provider'

export type PropertyType =
  | 'house'
  | 'apartment'
  | 'villa'
  | 'condo'
  | 'townhouse'
  | 'studio'
  | 'other'

export type HeatingType =
  | 'gas'
  | 'electric'
  | 'heat_pump'
  | 'oil'
  | 'wood'
  | 'district'
  | 'solar'
  | 'other'

export type MemberStatus = 'active' | 'inactive' | 'pending_invite' | 'suspended'
export type InvitationStatus = 'pending' | 'accepted' | 'declined' | 'expired' | 'revoked'
export type ItemCondition = 'excellent' | 'good' | 'fair' | 'poor' | 'broken'
export type TaskPriority = 'critical' | 'high' | 'medium' | 'low'
export type TaskStatus = 'pending' | 'in_progress' | 'completed' | 'cancelled' | 'overdue'
export type TaskCategory =
  | 'maintenance'
  | 'repair'
  | 'inspection'
  | 'cleaning'
  | 'upgrade'
  | 'administrative'
  | 'other'
export type DocumentCategory =
  | 'legal'
  | 'insurance'
  | 'warranty'
  | 'manual'
  | 'invoice'
  | 'permit'
  | 'tax'
  | 'utility'
  | 'other'
export type RoomType =
  | 'bedroom'
  | 'bathroom'
  | 'kitchen'
  | 'living_room'
  | 'dining_room'
  | 'office'
  | 'garage'
  | 'basement'
  | 'attic'
  | 'hallway'
  | 'laundry'
  | 'storage'
  | 'garden'
  | 'balcony'
  | 'terrace'
  | 'other'
export type NotificationPriority = 'critical' | 'high' | 'normal' | 'low'
export type NotificationStatus = 'unread' | 'read' | 'dismissed' | 'actioned'
export type FinanceCategory =
  | 'maintenance' | 'utilities' | 'insurance' | 'mortgage' | 'tax'
  | 'renovation' | 'appliance' | 'subscription' | 'other'
export type FinanceType = 'expense' | 'income' | 'budget'

// Migration 005 enums
export type MeterType = 'electricity' | 'gas' | 'water' | 'solar' | 'district_heating' | 'other'
export type EnergyUnit = 'kWh' | 'm3' | 'L' | 'GJ' | 'other'
export type GardenZoneType = 'bed' | 'lawn' | 'pot' | 'greenhouse' | 'orchard' | 'terrace' | 'other'
export type PlantStatus = 'healthy' | 'needs_attention' | 'dormant' | 'removed' | 'harvested'
export type GardenTaskType = 'watering' | 'fertilizing' | 'pruning' | 'harvesting' | 'planting' | 'pest_control' | 'repotting' | 'weeding' | 'general'
export type GardenTaskStatus = 'pending' | 'done' | 'skipped'
export type SecurityMode = 'disarmed' | 'home' | 'away' | 'night' | 'vacation'
export type SecurityEventType =
  | 'armed' | 'disarmed' | 'motion_detected' | 'door_opened' | 'window_opened'
  | 'alarm_triggered' | 'alarm_cleared' | 'battery_low' | 'offline' | 'online' | 'test' | 'manual'
export type SecuritySeverity = 'info' | 'warning' | 'alert' | 'critical'

// ─── Row Types (declared before Database to avoid circular refs) ─────────────

export type Profile = {
  id: string
  email: string
  full_name: string
  display_name: string | null
  avatar_url: string | null
  phone: string | null
  locale: string
  timezone: string
  theme: 'dark' | 'light' | 'auto'
  motion_pref: 'full' | 'reduced' | 'none'
  onboarding_completed: boolean
  onboarding_step: number
  last_seen_at: string | null
  created_at: string
  updated_at: string
}

export type Property = {
  id: string
  name: string
  address_line1: string
  address_line2: string | null
  city: string
  state_province: string | null
  postal_code: string | null
  country: string
  latitude: number | null
  longitude: number | null
  property_type: PropertyType
  size_sqm: number | null
  year_built: number | null
  year_renovated: number | null
  num_rooms: number | null
  num_bathrooms: number | null
  num_floors: number | null
  heating_type: HeatingType | null
  photo_url: string | null
  thumbnail_url: string | null
  timezone: string
  currency: string
  is_active: boolean
  health_score: number | null
  health_updated_at: string | null
  metadata: Json
  created_at: string
  updated_at: string
}

export type PropertyMember = {
  id: string
  property_id: string
  user_id: string | null
  role: UserRole
  status: MemberStatus
  nickname: string | null
  color: string | null
  permissions: Json
  invited_by: string | null
  joined_at: string
  created_at: string
  updated_at: string
}

export type PropertyInvitation = {
  id: string
  property_id: string
  invited_by: string
  email: string
  role: UserRole
  token: string
  status: InvitationStatus
  message: string | null
  expires_at: string
  accepted_at: string | null
  created_at: string
}

export type Room = {
  id: string
  property_id: string
  name: string
  room_type: RoomType
  floor: number
  area_sqm: number | null
  notes: string | null
  sort_order: number
  // Digital Twin positioning (migration 005)
  floor_plan_id: string | null
  x_pct: number | null
  y_pct: number | null
  width_pct: number | null
  height_pct: number | null
  color: string | null
  icon: string | null
  created_at: string
  updated_at: string
}

export type InventoryItem = {
  id: string
  property_id: string
  room_id: string | null
  name: string
  brand: string | null
  model: string | null
  serial_number: string | null
  category: string | null
  condition: ItemCondition | null
  purchase_date: string | null
  purchase_price: number | null
  purchase_currency: string | null
  current_value: number | null
  warranty_expires: string | null
  warranty_provider: string | null
  recall_active: boolean
  manual_url: string | null
  photo_urls: string[]
  barcode: string | null
  qr_code: string | null
  notes: string | null
  tags: string[]
  metadata: Json
  added_by: string | null
  created_at: string
  updated_at: string
}

export type MaintenanceTask = {
  id: string
  property_id: string
  room_id: string | null
  inventory_item_id: string | null
  title: string
  description: string | null
  category: TaskCategory
  priority: TaskPriority
  status: TaskStatus
  due_date: string | null
  scheduled_date: string | null
  completed_date: string | null
  estimated_hours: number | null
  actual_hours: number | null
  estimated_cost: number | null
  actual_cost: number | null
  cost_currency: string | null
  is_recurring: boolean
  recurrence_rule: string | null
  next_due_date: string | null
  parent_task_id: string | null
  assigned_to_member_id: string | null
  contractor_name: string | null
  contractor_phone: string | null
  contractor_email: string | null
  before_photo_urls: string[]
  after_photo_urls: string[]
  checklist: Json
  notes: string | null
  tags: string[]
  created_by: string | null
  created_at: string
  updated_at: string
}

export type Document = {
  id: string
  property_id: string
  inventory_item_id: string | null
  name: string
  description: string | null
  category: DocumentCategory
  file_url: string
  file_name: string
  file_size: number | null
  mime_type: string | null
  thumbnail_url: string | null
  tags: string[]
  expires_at: string | null
  is_critical: boolean
  uploaded_by: string | null
  created_at: string
  updated_at: string
}

export type Notification = {
  id: string
  property_id: string | null
  user_id: string
  title: string
  body: string | null
  priority: NotificationPriority
  status: NotificationStatus
  module: string | null
  action_url: string | null
  resource_type: string | null
  resource_id: string | null
  metadata: Json
  read_at: string | null
  created_at: string
}

export type FinancialRecord = {
  id: string
  property_id: string
  title: string
  amount: number
  currency: string
  type: FinanceType
  category: FinanceCategory
  date: string
  description: string | null
  maintenance_task_id: string | null
  receipt_url: string | null
  tags: string[]
  created_by: string | null
  created_at: string
  updated_at: string
}

export type AriaMessage = {
  id: string
  user_id: string
  property_id: string | null
  role: 'user' | 'assistant'
  content: string
  created_at: string
}

// ─── Migration 005 Row Types ──────────────────────────────────────────────────

export type EnergyReading = {
  id: string
  property_id: string
  reading_date: string
  meter_type: MeterType
  reading_value: number
  unit: EnergyUnit
  cost: number | null
  cost_currency: string | null
  provider: string | null
  meter_id: string | null
  notes: string | null
  created_by: string | null
  created_at: string
}

export type GardenZone = {
  id: string
  property_id: string
  name: string
  zone_type: GardenZoneType
  size_sqm: number | null
  sun_exposure: 'full_sun' | 'partial_shade' | 'full_shade' | null
  soil_type: string | null
  notes: string | null
  sort_order: number
  created_at: string
  updated_at: string
}

export type GardenPlant = {
  id: string
  property_id: string
  zone_id: string | null
  name: string
  species: string | null
  common_name: string | null
  planted_date: string | null
  status: PlantStatus
  watering_frequency_days: number | null
  last_watered: string | null
  next_watering: string | null
  fertilizing_frequency_days: number | null
  last_fertilized: string | null
  sunlight_needs: 'full_sun' | 'partial_shade' | 'full_shade' | 'shade' | null
  notes: string | null
  image_url: string | null
  tags: string[]
  created_at: string
  updated_at: string
}

export type GardenTask = {
  id: string
  property_id: string
  plant_id: string | null
  zone_id: string | null
  title: string
  task_type: GardenTaskType
  status: GardenTaskStatus
  due_date: string | null
  completed_date: string | null
  notes: string | null
  is_recurring: boolean
  recurrence_rule: string | null
  created_at: string
  updated_at: string
}

export type SecurityState = {
  id: string
  property_id: string
  mode: SecurityMode
  is_armed: boolean
  armed_at: string | null
  armed_by: string | null
  updated_at: string
}

export type SecurityEvent = {
  id: string
  property_id: string
  event_type: SecurityEventType
  device_id: string | null
  severity: SecuritySeverity
  description: string | null
  resolved_at: string | null
  created_by: string | null
  created_at: string
}

export type PropertyHealthHistory = {
  id: string
  property_id: string
  score: number
  recorded_at: string
}

export type SecuritySchedule = {
  id: string
  property_id: string
  label: string | null
  mode: SecurityMode
  days_of_week: number[]
  time_hhmm: string
  enabled: boolean
  created_at: string
}

export type FloorPlan = {
  id: string
  property_id: string
  name: string
  floor_number: number
  svg_data: string | null
  image_url: string | null
  width_m: number | null
  length_m: number | null
  sort_order: number
  created_at: string
  updated_at: string
}

// ─── Migration 006 Row Types ──────────────────────────────────────────────────

export type ServiceRequestStatus = 'pending' | 'quoted' | 'scheduled' | 'in_progress' | 'completed' | 'cancelled'

export type MarketplaceContact = {
  id: string
  property_id: string
  name: string
  category: string
  description: string | null
  phone: string | null
  email: string | null
  website: string | null
  notes: string | null
  rating: number | null
  is_favorite: boolean
  tags: string[]
  created_by: string | null
  created_at: string
  updated_at: string
}

export type ServiceRequest = {
  id: string
  property_id: string
  contact_id: string | null
  maintenance_task_id: string | null
  title: string
  description: string | null
  status: ServiceRequestStatus
  quoted_price: number | null
  cost_currency: string
  scheduled_date: string | null
  completed_date: string | null
  notes: string | null
  created_by: string | null
  created_at: string
  updated_at: string
}

// ─── Database Type (Supabase client generic) ─────────────────────────────────

export type Database = {
  public: {
    Tables: {
      profiles: {
        Row: Profile
        Insert: Partial<Profile> & { id: string; email: string }
        Update: Partial<Profile>
        Relationships: []
      }
      properties: {
        Row: Property
        Insert: Omit<Property, 'id' | 'created_at' | 'updated_at' | 'health_score' | 'health_updated_at'>
        Update: Partial<Property>
        Relationships: []
      }
      property_members: {
        Row: PropertyMember
        Insert: Omit<PropertyMember, 'id' | 'created_at' | 'updated_at' | 'joined_at'>
        Update: Partial<PropertyMember>
        Relationships: []
      }
      property_invitations: {
        Row: PropertyInvitation
        Insert: Omit<PropertyInvitation, 'id' | 'created_at' | 'token'>
        Update: Partial<PropertyInvitation>
        Relationships: []
      }
      rooms: {
        Row: Room
        Insert: Omit<Room, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<Room>
        Relationships: []
      }
      inventory_items: {
        Row: InventoryItem
        Insert: Omit<InventoryItem, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<InventoryItem>
        Relationships: []
      }
      maintenance_tasks: {
        Row: MaintenanceTask
        Insert: Omit<MaintenanceTask, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<MaintenanceTask>
        Relationships: []
      }
      documents: {
        Row: Document
        Insert: Omit<Document, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<Document>
        Relationships: []
      }
      notifications: {
        Row: Notification
        Insert: Omit<Notification, 'id' | 'created_at'>
        Update: Partial<Notification>
        Relationships: []
      }
      financial_records: {
        Row: FinancialRecord
        Insert: Omit<FinancialRecord, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<FinancialRecord>
        Relationships: []
      }
      aria_messages: {
        Row: AriaMessage
        Insert: Omit<AriaMessage, 'id' | 'created_at'>
        Update: Partial<AriaMessage>
        Relationships: []
      }
      energy_readings: {
        Row: EnergyReading
        Insert: Omit<EnergyReading, 'id' | 'created_at'>
        Update: Partial<EnergyReading>
        Relationships: []
      }
      garden_zones: {
        Row: GardenZone
        Insert: Omit<GardenZone, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<GardenZone>
        Relationships: []
      }
      garden_plants: {
        Row: GardenPlant
        Insert: Omit<GardenPlant, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<GardenPlant>
        Relationships: []
      }
      garden_tasks: {
        Row: GardenTask
        Insert: Omit<GardenTask, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<GardenTask>
        Relationships: []
      }
      security_state: {
        Row: SecurityState
        Insert: Omit<SecurityState, 'id' | 'updated_at'>
        Update: Partial<SecurityState>
        Relationships: []
      }
      security_events: {
        Row: SecurityEvent
        Insert: Omit<SecurityEvent, 'id' | 'created_at'>
        Update: Partial<SecurityEvent>
        Relationships: []
      }
      floor_plans: {
        Row: FloorPlan
        Insert: Omit<FloorPlan, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<FloorPlan>
        Relationships: []
      }
      security_schedules: {
        Row: SecuritySchedule
        Insert: Omit<SecuritySchedule, 'id' | 'created_at'>
        Update: Partial<SecuritySchedule>
        Relationships: []
      }
      property_health_history: {
        Row: PropertyHealthHistory
        Insert: Omit<PropertyHealthHistory, 'id'>
        Update: Partial<PropertyHealthHistory>
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      get_my_property_role: {
        Args: { p_property_id: string }
        Returns: UserRole
      }
      is_property_owner_or_partner: {
        Args: { p_property_id: string }
        Returns: boolean
      }
      has_property_write_access: {
        Args: { p_property_id: string }
        Returns: boolean
      }
      is_property_member: {
        Args: { p_property_id: string }
        Returns: boolean
      }
      compute_health_score: {
        Args: { p_property_id: string }
        Returns: number
      }
      create_doc_expiry_notifications: {
        Args: { p_user_id: string }
        Returns: void
      }
      create_recall_notifications: {
        Args: { p_user_id: string }
        Returns: void
      }
      create_overdue_task_notifications: {
        Args: { p_user_id: string }
        Returns: void
      }
      set_security_mode: {
        Args: { p_property_id: string; p_mode: SecurityMode }
        Returns: void
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

// ─── Extended Types (with joins) ─────────────────────────────────────────────

export type PropertyWithMembers = Property & {
  property_members: PropertyMember[]
}

export type PropertyMemberWithProfile = PropertyMember & {
  profiles: Profile | null
}

export type MaintenanceTaskWithRelations = MaintenanceTask & {
  rooms: Room | null
  inventory_items: InventoryItem | null
}

// ─── Role Hierarchy ──────────────────────────────────────────────────────────

export const ROLE_HIERARCHY: Record<UserRole, number> = {
  owner: 100,
  partner: 90,
  family_adult: 70,
  family_teen: 50,
  family_child: 30,
  family_elderly: 50,
  tenant: 40,
  guest: 10,
  service_provider: 20,
}

export const ROLE_LABELS: Record<UserRole, string> = {
  owner: 'Owner',
  partner: 'Partner',
  family_adult: 'Family Member',
  family_teen: 'Teen',
  family_child: 'Child',
  family_elderly: 'Elderly Parent',
  tenant: 'Tenant',
  guest: 'Guest',
  service_provider: 'Service Provider',
}

export function hasMinRole(userRole: UserRole, minRole: UserRole): boolean {
  return ROLE_HIERARCHY[userRole] >= ROLE_HIERARCHY[minRole]
}
