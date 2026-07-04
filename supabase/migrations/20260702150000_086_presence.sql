-- 086 — lightweight presence (online / last seen) per property member
--
-- A heartbeat row per (property, user). Clients upsert their own row every
-- ~45s while foregrounded; co-members read the table to show "online" (seen
-- within the last ~90s) or "last seen {relative}". Mirrors 075 live_locations:
-- a dedicated table with is_property_member RLS, so we never expose profiles
-- across users. Sharing is opt-out client-side (a member who disables it
-- simply stops heartbeating and appears offline).

create table if not exists public.presence (
  property_id  uuid not null references public.properties(id) on delete cascade,
  user_id      uuid not null,
  user_name    text not null,
  last_seen_at timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (property_id, user_id)
);
create index if not exists presence_prop_idx on public.presence(property_id);

alter table public.presence enable row level security;

drop policy if exists members_select on public.presence;
create policy members_select on public.presence
  for select using (public.is_property_member(property_id));

drop policy if exists own_insert on public.presence;
create policy own_insert on public.presence
  for insert with check (public.is_property_member(property_id) and user_id = auth.uid());

drop policy if exists own_update on public.presence;
create policy own_update on public.presence
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists own_delete on public.presence;
create policy own_delete on public.presence
  for delete using (user_id = auth.uid());
