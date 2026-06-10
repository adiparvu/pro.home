-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 002: Property Modules (Inventory, Maintenance, Docs)
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Enum Types ─────────────────────────────────────────────────────────────

create type item_condition as enum ('excellent', 'good', 'fair', 'poor', 'broken');
create type task_priority as enum ('critical', 'high', 'medium', 'low');
create type task_status as enum ('pending', 'in_progress', 'completed', 'cancelled', 'overdue');
create type task_category as enum ('maintenance', 'repair', 'inspection', 'cleaning', 'upgrade', 'administrative', 'other');
create type document_category as enum ('legal', 'insurance', 'warranty', 'manual', 'invoice', 'permit', 'tax', 'utility', 'other');
create type room_type as enum ('bedroom', 'bathroom', 'kitchen', 'living_room', 'dining_room', 'office', 'garage', 'basement', 'attic', 'hallway', 'laundry', 'storage', 'garden', 'balcony', 'terrace', 'other');

-- ─── Rooms Table ─────────────────────────────────────────────────────────────

create table public.rooms (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references public.properties(id) on delete cascade,
  name          text not null,
  room_type     room_type not null default 'other',
  floor         smallint not null default 0,
  area_sqm      numeric(6, 2),
  notes         text,
  sort_order    smallint not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.rooms is 'Rooms within a property for organizing inventory and features.';

-- ─── Inventory Items Table ───────────────────────────────────────────────────

create table public.inventory_items (
  id                uuid primary key default gen_random_uuid(),
  property_id       uuid not null references public.properties(id) on delete cascade,
  room_id           uuid references public.rooms(id) on delete set null,
  name              text not null,
  brand             text,
  model             text,
  serial_number     text,
  category          text,                   -- Appliances, Electronics, Furniture, Tools, etc.
  condition         item_condition,
  purchase_date     date,
  purchase_price    numeric(12, 2),
  purchase_currency text default 'EUR',
  current_value     numeric(12, 2),
  warranty_expires  date,
  warranty_provider text,
  recall_active     boolean not null default false,
  manual_url        text,
  photo_urls        text[] not null default '{}',
  barcode           text,
  qr_code           text,
  notes             text,
  tags              text[] not null default '{}',
  metadata          jsonb not null default '{}',  -- M-SCAN™ raw data stored here
  added_by          uuid references public.profiles(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.inventory_items is 'Property inventory — appliances, electronics, furniture, tools.';

-- ─── Maintenance Tasks Table ─────────────────────────────────────────────────

create table public.maintenance_tasks (
  id               uuid primary key default gen_random_uuid(),
  property_id      uuid not null references public.properties(id) on delete cascade,
  room_id          uuid references public.rooms(id) on delete set null,
  inventory_item_id uuid references public.inventory_items(id) on delete set null,
  title            text not null,
  description      text,
  category         task_category not null default 'maintenance',
  priority         task_priority not null default 'medium',
  status           task_status not null default 'pending',
  due_date         date,
  scheduled_date   date,
  completed_date   date,
  estimated_hours  numeric(4, 1),
  actual_hours     numeric(4, 1),
  estimated_cost   numeric(12, 2),
  actual_cost      numeric(12, 2),
  cost_currency    text default 'EUR',
  -- Recurrence
  is_recurring     boolean not null default false,
  recurrence_rule  text,       -- iCal RRULE format
  next_due_date    date,
  parent_task_id   uuid references public.maintenance_tasks(id),
  -- Assignment
  assigned_to_member_id uuid references public.property_members(id),
  contractor_name  text,
  contractor_phone text,
  contractor_email text,
  -- Completion evidence
  before_photo_urls text[] not null default '{}',
  after_photo_urls  text[] not null default '{}',
  checklist         jsonb not null default '[]',  -- [{text, done}]
  notes             text,
  tags              text[] not null default '{}',
  created_by        uuid references public.profiles(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.maintenance_tasks is 'Maintenance and repair tasks for the property.';

-- ─── Documents Table ──────────────────────────────────────────────────────────

create table public.documents (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references public.properties(id) on delete cascade,
  inventory_item_id uuid references public.inventory_items(id) on delete set null,
  name          text not null,
  description   text,
  category      document_category not null default 'other',
  file_url      text not null,
  file_name     text not null,
  file_size     bigint,
  mime_type     text,
  thumbnail_url text,
  tags          text[] not null default '{}',
  expires_at    date,
  is_critical   boolean not null default false,
  uploaded_by   uuid references public.profiles(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.documents is 'Property documents, warranties, manuals, legal docs.';

-- ─── Property Health Score Components ────────────────────────────────────────

create table public.health_scores (
  id               uuid primary key default gen_random_uuid(),
  property_id      uuid not null references public.properties(id) on delete cascade,
  total_score      smallint not null check (total_score >= 0 and total_score <= 100),
  maintenance_score   smallint check (maintenance_score >= 0 and maintenance_score <= 100),
  safety_score     smallint check (safety_score >= 0 and safety_score <= 100),
  energy_score     smallint check (energy_score >= 0 and energy_score <= 100),
  document_score   smallint check (document_score >= 0 and document_score <= 100),
  system_score     smallint check (system_score >= 0 and system_score <= 100),
  insurance_score  smallint check (insurance_score >= 0 and insurance_score <= 100),
  financial_score  smallint check (financial_score >= 0 and financial_score <= 100),
  computed_at      timestamptz not null default now(),
  notes            text
);

comment on table public.health_scores is 'Time-series health score snapshots for properties.';

-- ─── Notifications Table ─────────────────────────────────────────────────────

create type notification_priority as enum ('critical', 'high', 'normal', 'low');
create type notification_status as enum ('unread', 'read', 'dismissed', 'actioned');

create table public.notifications (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid references public.properties(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  title         text not null,
  body          text,
  priority      notification_priority not null default 'normal',
  status        notification_status not null default 'unread',
  module        text,                -- home|property|security|energy|...
  action_url    text,
  resource_type text,
  resource_id   uuid,
  metadata      jsonb not null default '{}',
  read_at       timestamptz,
  created_at    timestamptz not null default now()
);

comment on table public.notifications is 'In-app notifications for users.';

-- ─── Indexes ─────────────────────────────────────────────────────────────────

create index idx_rooms_property on public.rooms(property_id);
create index idx_inventory_property on public.inventory_items(property_id);
create index idx_inventory_room on public.inventory_items(room_id);
create index idx_inventory_warranty on public.inventory_items(warranty_expires) where warranty_expires is not null;
create index idx_tasks_property on public.maintenance_tasks(property_id);
create index idx_tasks_status on public.maintenance_tasks(property_id, status);
create index idx_tasks_due on public.maintenance_tasks(due_date) where status not in ('completed', 'cancelled');
create index idx_documents_property on public.documents(property_id);
create index idx_documents_category on public.documents(property_id, category);
create index idx_health_property on public.health_scores(property_id, computed_at desc);
create index idx_notifications_user on public.notifications(user_id, created_at desc);
create index idx_notifications_unread on public.notifications(user_id) where status = 'unread';

-- ─── Updated-At Triggers ─────────────────────────────────────────────────────

create trigger rooms_updated_at
  before update on public.rooms
  for each row execute function public.set_updated_at();

create trigger inventory_items_updated_at
  before update on public.inventory_items
  for each row execute function public.set_updated_at();

create trigger maintenance_tasks_updated_at
  before update on public.maintenance_tasks
  for each row execute function public.set_updated_at();

create trigger documents_updated_at
  before update on public.documents
  for each row execute function public.set_updated_at();

-- ─── Row Level Security ──────────────────────────────────────────────────────

alter table public.rooms enable row level security;
alter table public.inventory_items enable row level security;
alter table public.maintenance_tasks enable row level security;
alter table public.documents enable row level security;
alter table public.health_scores enable row level security;
alter table public.notifications enable row level security;

-- Rooms
create policy "rooms_select_member" on public.rooms for select
  using (public.is_property_member(property_id));
create policy "rooms_write_write_access" on public.rooms for insert
  with check (public.has_property_write_access(property_id));
create policy "rooms_update_write_access" on public.rooms for update
  using (public.has_property_write_access(property_id));
create policy "rooms_delete_owner" on public.rooms for delete
  using (public.is_property_owner_or_partner(property_id));

-- Inventory
create policy "inventory_select_member" on public.inventory_items for select
  using (public.is_property_member(property_id));
create policy "inventory_insert_write" on public.inventory_items for insert
  with check (public.has_property_write_access(property_id));
create policy "inventory_update_write" on public.inventory_items for update
  using (public.has_property_write_access(property_id));
create policy "inventory_delete_owner" on public.inventory_items for delete
  using (public.is_property_owner_or_partner(property_id));

-- Maintenance tasks
create policy "tasks_select_member" on public.maintenance_tasks for select
  using (public.is_property_member(property_id));
create policy "tasks_insert_write" on public.maintenance_tasks for insert
  with check (public.has_property_write_access(property_id));
create policy "tasks_update_write" on public.maintenance_tasks for update
  using (public.has_property_write_access(property_id));
create policy "tasks_delete_owner" on public.maintenance_tasks for delete
  using (public.is_property_owner_or_partner(property_id));

-- Documents
create policy "documents_select_member" on public.documents for select
  using (public.is_property_member(property_id));
create policy "documents_insert_write" on public.documents for insert
  with check (public.has_property_write_access(property_id));
create policy "documents_update_write" on public.documents for update
  using (public.has_property_write_access(property_id));
create policy "documents_delete_owner" on public.documents for delete
  using (public.is_property_owner_or_partner(property_id));

-- Health scores: members read, system writes
create policy "health_select_member" on public.health_scores for select
  using (public.is_property_member(property_id));

-- Notifications: users see only their own
create policy "notifications_own" on public.notifications for all
  using (user_id = auth.uid());

-- ─── Health Score Computation Function ───────────────────────────────────────

create or replace function public.compute_health_score(p_property_id uuid)
returns smallint
language plpgsql security definer
set search_path = public
as $$
declare
  v_overdue_tasks       integer;
  v_total_tasks_30d     integer;
  v_expired_warranties  integer;
  v_total_inventory     integer;
  v_expired_docs        integer;
  v_critical_docs       integer;
  v_maintenance_score   smallint;
  v_document_score      smallint;
  v_total_score         smallint;
begin
  -- Maintenance factor (weight 30%)
  select count(*) into v_overdue_tasks
  from public.maintenance_tasks
  where property_id = p_property_id
    and status = 'overdue';

  select count(*) into v_total_tasks_30d
  from public.maintenance_tasks
  where property_id = p_property_id
    and due_date >= now() - interval '30 days';

  if v_total_tasks_30d = 0 then
    v_maintenance_score := 85;
  else
    v_maintenance_score := greatest(0, 100 - (v_overdue_tasks * 15))::smallint;
  end if;

  -- Document factor (weight 10%)
  select count(*) into v_expired_docs
  from public.documents
  where property_id = p_property_id
    and expires_at < now()
    and is_critical = true;

  v_document_score := greatest(0, 100 - (v_expired_docs * 20))::smallint;

  -- Weighted total (simplified — full algorithm in app layer)
  v_total_score := (
    v_maintenance_score * 0.30 +
    v_document_score * 0.10 +
    75 * 0.60  -- remaining factors default to 75 until more data
  )::smallint;

  -- Store the snapshot
  insert into public.health_scores (property_id, total_score, maintenance_score, document_score)
  values (p_property_id, v_total_score, v_maintenance_score, v_document_score);

  -- Update the property's cached score
  update public.properties
  set health_score = v_total_score,
      health_updated_at = now()
  where id = p_property_id;

  return v_total_score;
end;
$$;
