-- 101 — paint_colors
--
-- The iOS app has a full "Culori vopsea" (paint colors) feature that reads and
-- writes public.paint_colors, but the table was never created — every add
-- silently failed ("relation does not exist"), so nothing showed up. Create it
-- to match the client model, scoped to the household.

create table if not exists public.paint_colors (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  owner_id uuid not null,
  room_name text not null,
  surface text not null,
  color_name text not null,
  brand text,
  code text,
  finish text,
  hex_color text,
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists paint_colors_property_idx on public.paint_colors(property_id);

alter table public.paint_colors enable row level security;

drop policy if exists paint_colors_read on public.paint_colors;
create policy paint_colors_read on public.paint_colors
  for select using (public.has_household_access(property_id));

drop policy if exists paint_colors_write on public.paint_colors;
create policy paint_colors_write on public.paint_colors
  for all
  using (public.has_household_access(property_id))
  with check (public.has_household_access(property_id));
