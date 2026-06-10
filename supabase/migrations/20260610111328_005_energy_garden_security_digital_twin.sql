-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 005: Energy, Garden, Security State, Digital Twin
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Energy Readings ─────────────────────────────────────────────────────────

create type meter_type as enum ('electricity', 'gas', 'water', 'solar', 'district_heating', 'other');
create type energy_unit as enum ('kWh', 'm3', 'L', 'GJ', 'other');

create table public.energy_readings (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references public.properties(id) on delete cascade,
  reading_date  date not null,
  meter_type    meter_type not null,
  reading_value numeric(12, 3) not null,
  unit          energy_unit not null default 'kWh',
  cost          numeric(10, 2),
  cost_currency text default 'EUR',
  provider      text,
  meter_id      text,
  notes         text,
  created_by    uuid references public.profiles(id),
  created_at    timestamptz not null default now()
);

comment on table public.energy_readings is 'Meter readings for electricity, gas, water, solar.';

-- ─── Garden ──────────────────────────────────────────────────────────────────

create type garden_zone_type as enum ('bed', 'lawn', 'pot', 'greenhouse', 'orchard', 'terrace', 'other');
create type plant_status as enum ('healthy', 'needs_attention', 'dormant', 'removed', 'harvested');
create type garden_task_type as enum ('watering', 'fertilizing', 'pruning', 'harvesting', 'planting', 'pest_control', 'repotting', 'weeding', 'general');
create type garden_task_status as enum ('pending', 'done', 'skipped');

create table public.garden_zones (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties(id) on delete cascade,
  name         text not null,
  zone_type    garden_zone_type not null default 'bed',
  size_sqm     numeric(8, 2),
  sun_exposure text check (sun_exposure in ('full_sun', 'partial_shade', 'full_shade')),
  soil_type    text,
  notes        text,
  sort_order   smallint not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table public.garden_plants (
  id                         uuid primary key default gen_random_uuid(),
  property_id                uuid not null references public.properties(id) on delete cascade,
  zone_id                    uuid references public.garden_zones(id) on delete set null,
  name                       text not null,
  species                    text,
  common_name                text,
  planted_date               date,
  status                     plant_status not null default 'healthy',
  watering_frequency_days    int,
  last_watered               date,
  next_watering              date,
  fertilizing_frequency_days int,
  last_fertilized            date,
  sunlight_needs             text check (sunlight_needs in ('full_sun', 'partial_shade', 'full_shade', 'shade')),
  notes                      text,
  image_url                  text,
  tags                       text[] not null default '{}',
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now()
);

create table public.garden_tasks (
  id              uuid primary key default gen_random_uuid(),
  property_id     uuid not null references public.properties(id) on delete cascade,
  plant_id        uuid references public.garden_plants(id) on delete set null,
  zone_id         uuid references public.garden_zones(id) on delete set null,
  title           text not null,
  task_type       garden_task_type not null default 'general',
  status          garden_task_status not null default 'pending',
  due_date        date,
  completed_date  date,
  notes           text,
  is_recurring    boolean not null default false,
  recurrence_rule text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table public.garden_zones  is 'Garden zones/beds within a property.';
comment on table public.garden_plants is 'Plants tracked per property with care schedules.';
comment on table public.garden_tasks  is 'Garden care tasks (watering, pruning, etc.).';

-- ─── Security State & Events ─────────────────────────────────────────────────

create type security_mode as enum ('disarmed', 'home', 'away', 'night', 'vacation');
create type security_event_type as enum (
  'armed', 'disarmed', 'motion_detected', 'door_opened', 'window_opened',
  'alarm_triggered', 'alarm_cleared', 'battery_low', 'offline', 'online', 'test', 'manual'
);
create type security_severity as enum ('info', 'warning', 'alert', 'critical');

create table public.security_state (
  id          uuid primary key default gen_random_uuid(),
  property_id uuid not null unique references public.properties(id) on delete cascade,
  mode        security_mode not null default 'disarmed',
  is_armed    boolean not null default false,
  armed_at    timestamptz,
  armed_by    uuid references public.profiles(id),
  updated_at  timestamptz not null default now()
);

create table public.security_events (
  id          uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  event_type  security_event_type not null,
  device_id   uuid references public.inventory_items(id) on delete set null,
  severity    security_severity not null default 'info',
  description text,
  resolved_at timestamptz,
  created_by  uuid references public.profiles(id),
  created_at  timestamptz not null default now()
);

comment on table public.security_state  is 'Current armed/mode state per property (one row per property).';
comment on table public.security_events is 'Security event log — arm/disarm, alerts, device events.';

-- ─── Digital Twin — Floor Plans ──────────────────────────────────────────────

create table public.floor_plans (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties(id) on delete cascade,
  name         text not null default 'Ground Floor',
  floor_number smallint not null default 0,
  svg_data     text,
  image_url    text,
  width_m      numeric(8, 2),
  length_m     numeric(8, 2),
  sort_order   smallint not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.floor_plans is 'Floor plan uploads / SVG data for Digital Twin.';

alter table public.rooms
  add column if not exists floor_plan_id uuid references public.floor_plans(id) on delete set null,
  add column if not exists x_pct         numeric(6, 2),
  add column if not exists y_pct         numeric(6, 2),
  add column if not exists width_pct     numeric(6, 2),
  add column if not exists height_pct    numeric(6, 2),
  add column if not exists color         text,
  add column if not exists icon          text;

-- ─── Indexes ─────────────────────────────────────────────────────────────────

create index idx_energy_property_date on public.energy_readings(property_id, reading_date desc);
create index idx_energy_meter_type    on public.energy_readings(property_id, meter_type);
create index idx_garden_zones_prop    on public.garden_zones(property_id);
create index idx_garden_plants_prop   on public.garden_plants(property_id);
create index idx_garden_plants_zone   on public.garden_plants(zone_id);
create index idx_garden_tasks_prop    on public.garden_tasks(property_id);
create index idx_garden_tasks_due     on public.garden_tasks(due_date) where status = 'pending';
create index idx_security_events_prop on public.security_events(property_id, created_at desc);
create index idx_floor_plans_prop     on public.floor_plans(property_id);
create index idx_rooms_floor_plan     on public.rooms(floor_plan_id) where floor_plan_id is not null;

-- ─── Updated-At Triggers ─────────────────────────────────────────────────────

create trigger garden_zones_updated_at   before update on public.garden_zones   for each row execute function public.set_updated_at();
create trigger garden_plants_updated_at  before update on public.garden_plants  for each row execute function public.set_updated_at();
create trigger garden_tasks_updated_at   before update on public.garden_tasks   for each row execute function public.set_updated_at();
create trigger floor_plans_updated_at    before update on public.floor_plans    for each row execute function public.set_updated_at();
create trigger security_state_updated_at before update on public.security_state for each row execute function public.set_updated_at();

-- ─── Row Level Security ───────────────────────────────────────────────────────

alter table public.energy_readings enable row level security;
alter table public.garden_zones    enable row level security;
alter table public.garden_plants   enable row level security;
alter table public.garden_tasks    enable row level security;
alter table public.security_state  enable row level security;
alter table public.security_events enable row level security;
alter table public.floor_plans     enable row level security;

create policy "energy_select" on public.energy_readings for select using (public.is_property_member(property_id));
create policy "energy_insert" on public.energy_readings for insert with check (public.has_property_write_access(property_id));
create policy "energy_update" on public.energy_readings for update using (public.has_property_write_access(property_id));
create policy "energy_delete" on public.energy_readings for delete using (public.is_property_owner_or_partner(property_id));

create policy "garden_zones_select" on public.garden_zones for select using (public.is_property_member(property_id));
create policy "garden_zones_insert" on public.garden_zones for insert with check (public.has_property_write_access(property_id));
create policy "garden_zones_update" on public.garden_zones for update using (public.has_property_write_access(property_id));
create policy "garden_zones_delete" on public.garden_zones for delete using (public.is_property_owner_or_partner(property_id));

create policy "garden_plants_select" on public.garden_plants for select using (public.is_property_member(property_id));
create policy "garden_plants_insert" on public.garden_plants for insert with check (public.has_property_write_access(property_id));
create policy "garden_plants_update" on public.garden_plants for update using (public.has_property_write_access(property_id));
create policy "garden_plants_delete" on public.garden_plants for delete using (public.is_property_owner_or_partner(property_id));

create policy "garden_tasks_select" on public.garden_tasks for select using (public.is_property_member(property_id));
create policy "garden_tasks_insert" on public.garden_tasks for insert with check (public.has_property_write_access(property_id));
create policy "garden_tasks_update" on public.garden_tasks for update using (public.has_property_write_access(property_id));
create policy "garden_tasks_delete" on public.garden_tasks for delete using (public.is_property_owner_or_partner(property_id));

create policy "security_state_select" on public.security_state for select using (public.is_property_member(property_id));
create policy "security_state_insert" on public.security_state for insert with check (public.has_property_write_access(property_id));
create policy "security_state_update" on public.security_state for update using (public.has_property_write_access(property_id));

create policy "security_events_select" on public.security_events for select using (public.is_property_member(property_id));
create policy "security_events_insert" on public.security_events for insert with check (public.has_property_write_access(property_id));

create policy "floor_plans_select" on public.floor_plans for select using (public.is_property_member(property_id));
create policy "floor_plans_insert" on public.floor_plans for insert with check (public.has_property_write_access(property_id));
create policy "floor_plans_update" on public.floor_plans for update using (public.has_property_write_access(property_id));
create policy "floor_plans_delete" on public.floor_plans for delete using (public.is_property_owner_or_partner(property_id));

-- ─── Security Mode RPC ───────────────────────────────────────────────────────

create or replace function public.set_security_mode(
  p_property_id uuid,
  p_mode        security_mode
)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.security_state (property_id, mode, is_armed, armed_at, armed_by)
  values (
    p_property_id, p_mode, p_mode <> 'disarmed',
    case when p_mode <> 'disarmed' then now() else null end,
    auth.uid()
  )
  on conflict (property_id) do update
    set mode     = excluded.mode,
        is_armed = excluded.is_armed,
        armed_at = case when excluded.mode <> 'disarmed' then now() else null end,
        armed_by = auth.uid(),
        updated_at = now();

  insert into public.security_events (property_id, event_type, severity, created_by)
  values (
    p_property_id,
    case when p_mode = 'disarmed' then 'disarmed'::security_event_type else 'armed'::security_event_type end,
    'info', auth.uid()
  );
end;
$$;

grant execute on function public.set_security_mode(uuid, security_mode) to authenticated;
