-- 075 — live location sharing (foreground real-time + duration window)

create table if not exists public.live_locations (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  user_id uuid not null,
  user_name text not null,
  lat double precision not null,
  lon double precision not null,
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  updated_at timestamptz not null default now(),
  unique (property_id, user_id)
);
create index if not exists live_locations_prop_exp_idx on public.live_locations(property_id, expires_at);

alter table public.live_locations enable row level security;

drop policy if exists members_select on public.live_locations;
create policy members_select on public.live_locations
  for select using (public.is_property_member(property_id));

drop policy if exists owner_insert on public.live_locations;
create policy owner_insert on public.live_locations
  for insert with check (public.is_property_member(property_id) and user_id = auth.uid());

drop policy if exists owner_update on public.live_locations;
create policy owner_update on public.live_locations
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists owner_delete on public.live_locations;
create policy owner_delete on public.live_locations
  for delete using (user_id = auth.uid());
