-- Digital Property Twin — Zones layer
-- Adds a hierarchical Property → Zones → Objects model on top of the existing
-- property_elements ("objects") table. Zones are polygons drawn over the
-- satellite map; objects can optionally be geo-located and assigned to a zone.

-- 1. Zones -------------------------------------------------------------------

create table if not exists public.property_zones (
    id            uuid        primary key default gen_random_uuid(),
    property_id   uuid        not null references public.properties(id) on delete cascade,
    name          text        not null,
    icon          text        not null default 'square.dashed',
    color_hex     text        not null default '#34C759',
    layer         text        not null default 'property',
    health_score  int         not null default 100 check (health_score between 0 and 100),
    -- polygon stored as ordered array of {"lat": Double, "lon": Double}
    polygon       jsonb       not null default '[]'::jsonb,
    notes         text,
    sort_order    int         not null default 0,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create index if not exists property_zones_property_id_idx
    on public.property_zones (property_id);

-- 2. Geo-locate objects + link them to a zone --------------------------------

alter table public.property_elements
    add column if not exists latitude  double precision,
    add column if not exists longitude double precision,
    add column if not exists zone_id   uuid references public.property_zones(id) on delete set null;

create index if not exists property_elements_zone_id_idx
    on public.property_elements (zone_id);

-- 3. updated_at trigger ------------------------------------------------------

create or replace function public.set_property_zones_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists property_zones_updated_at on public.property_zones;
create trigger property_zones_updated_at
    before update on public.property_zones
    for each row execute function public.set_property_zones_updated_at();

-- 4. RLS ---------------------------------------------------------------------
-- Mirrors property_elements exactly, reusing the shared helper functions.

alter table public.property_zones enable row level security;

drop policy if exists "property_zones_select" on public.property_zones;
create policy "property_zones_select" on public.property_zones
  for select using (public.is_property_member(property_id));

drop policy if exists "property_zones_insert" on public.property_zones;
create policy "property_zones_insert" on public.property_zones
  for insert with check (public.has_property_write_access(property_id));

drop policy if exists "property_zones_update" on public.property_zones;
create policy "property_zones_update" on public.property_zones
  for update using (public.has_property_write_access(property_id));

drop policy if exists "property_zones_delete" on public.property_zones;
create policy "property_zones_delete" on public.property_zones
  for delete using (public.is_property_owner_or_partner(property_id));
