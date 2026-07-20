-- 159: rooms ↔ property_zones bridge.
--
-- The app carries two parallel "space" models that only ever met by name:
-- property_zones (Tab 2's spaces — photos, health, kind) and rooms (the
-- Blueprints floor plan — level, percent rectangle, RoomPlan scan). This
-- gives rooms an id-link to the zone they represent on the plan, so the
-- Spaces tab can render the interactive floor plan and RoomPlan scans can
-- attach to a space without fragile name joins.

create extension if not exists unaccent;

alter table public.rooms
    add column if not exists zone_id uuid references public.property_zones(id) on delete set null;

create index if not exists rooms_zone_idx on public.rooms (zone_id);

-- One-time backfill: same property, case/diacritic-insensitive name equality
-- (the exact match rule the app already applies everywhere the two worlds meet).
update public.rooms r
set zone_id = z.id
from public.property_zones z
where r.zone_id is null
  and z.property_id = r.property_id
  and lower(unaccent(btrim(r.name))) = lower(unaccent(btrim(z.name)));
