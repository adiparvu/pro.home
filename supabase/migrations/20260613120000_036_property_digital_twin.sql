-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 036: Property Digital Twin — Elements & Records
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Property Elements ───────────────────────────────────────────────────────
-- Represents every physical element of a property: house, garage, trees,
-- pool, fences, solar panels, cameras, boiler, etc.

create table if not exists public.property_elements (
  id                 uuid        primary key default gen_random_uuid(),
  property_id        uuid        not null references public.properties(id) on delete cascade,
  name               text        not null,
  element_type       text        not null,   -- 'house' | 'garage' | 'pool' | 'tree' | ...
  description        text,
  position_x         float       not null default 0.5,  -- 0.0–1.0 relative to canvas
  position_y         float       not null default 0.5,
  health_score       int         not null default 100 check (health_score between 0 and 100),
  technical_condition text       not null default 'good',
  estimated_value    float,
  value_currency     text        not null default 'EUR',
  purchase_date      date,
  warranty_until     date,
  brand              text,
  model              text,
  serial_number      text,
  notes              text,
  layer              text        not null default 'property',
  sort_order         int         not null default 0,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

alter table public.property_elements enable row level security;

create policy "property_elements_select" on public.property_elements
  for select using (public.is_property_member(property_id));
create policy "property_elements_insert" on public.property_elements
  for insert with check (public.has_property_write_access(property_id));
create policy "property_elements_update" on public.property_elements
  for update using (public.has_property_write_access(property_id));
create policy "property_elements_delete" on public.property_elements
  for delete using (public.is_property_owner_or_partner(property_id));

create index idx_property_elements_property on public.property_elements(property_id);

create trigger property_elements_updated_at
  before update on public.property_elements
  for each row execute function public.set_updated_at();

-- ─── Element Records ─────────────────────────────────────────────────────────
-- Generic record log per element: maintenance events, notes, cost entries,
-- inspections, and scheduled reminders.

create table if not exists public.element_records (
  id               uuid        primary key default gen_random_uuid(),
  element_id       uuid        not null references public.property_elements(id) on delete cascade,
  property_id      uuid        not null references public.properties(id) on delete cascade,
  record_type      text        not null default 'note', -- 'note'|'maintenance'|'cost'|'inspection'|'reminder'
  title            text        not null,
  content          text,
  cost             float,
  currency         text        not null default 'EUR',
  record_date      date        not null default current_date,
  performed_by     text,
  next_action_date date,
  created_at       timestamptz not null default now()
);

alter table public.element_records enable row level security;

create policy "element_records_select" on public.element_records
  for select using (public.is_property_member(property_id));
create policy "element_records_insert" on public.element_records
  for insert with check (public.has_property_write_access(property_id));
create policy "element_records_update" on public.element_records
  for update using (public.has_property_write_access(property_id));
create policy "element_records_delete" on public.element_records
  for delete using (public.is_property_owner_or_partner(property_id));

create index idx_element_records_element  on public.element_records(element_id);
create index idx_element_records_property on public.element_records(property_id);
create index idx_element_records_date     on public.element_records(element_id, record_date desc);

-- ─── Property Health Score RPC ───────────────────────────────────────────────
-- Recalculates property health score from element scores.

create or replace function public.refresh_property_health_score(p_property_id uuid)
returns int
language plpgsql security definer
set search_path = public
as $$
declare
  v_score int;
begin
  select coalesce(round(avg(health_score))::int, 100)
  into v_score
  from public.property_elements
  where property_id = p_property_id;

  update public.properties
  set health_score = v_score, updated_at = now()
  where id = p_property_id;

  return v_score;
end;
$$;

grant execute on function public.refresh_property_health_score(uuid) to authenticated;
