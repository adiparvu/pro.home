-- 160: home presence — geofenced "who's home" state + arrival/departure events.
--
-- Fed by the app's CLCircularRegion transitions (opt-in per user, default
-- off). One durable state row per (property, member) for the family card,
-- plus an append-only event trail for the house timeline and the rules
-- engine's geofence condition. RLS: members read the household; each user
-- writes ONLY their own rows, and delete-own powers "opting out erases me".

create table if not exists public.home_presence (
    property_id uuid not null references public.properties(id) on delete cascade,
    user_id     uuid not null references auth.users(id) on delete cascade,
    user_name   text not null,
    is_home     boolean not null,
    since       timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    primary key (property_id, user_id)
);

create table if not exists public.home_presence_events (
    id          uuid primary key default gen_random_uuid(),
    property_id uuid not null references public.properties(id) on delete cascade,
    user_id     uuid not null default auth.uid(),
    user_name   text not null,
    event       text not null check (event in ('arrive', 'leave')),
    created_at  timestamptz not null default now()
);

create index if not exists home_presence_events_prop_time_idx
    on public.home_presence_events (property_id, created_at desc);

alter table public.home_presence enable row level security;
alter table public.home_presence_events enable row level security;

create policy home_presence_select on public.home_presence
    for select using (public.is_property_member(property_id));
create policy home_presence_insert on public.home_presence
    for insert with check (auth.uid() = user_id and public.is_property_member(property_id));
create policy home_presence_update on public.home_presence
    for update using (auth.uid() = user_id);
create policy home_presence_delete on public.home_presence
    for delete using (auth.uid() = user_id);

create policy home_presence_events_select on public.home_presence_events
    for select using (public.is_property_member(property_id));
create policy home_presence_events_insert on public.home_presence_events
    for insert with check (auth.uid() = user_id and public.is_property_member(property_id));

-- The state table streams to the family card; events are read on demand.
alter publication supabase_realtime add table public.home_presence;
