-- 074 — Status / Stories: 24h ephemeral updates + per-viewer seen tracking

create table if not exists public.status_updates (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  author_id uuid not null,
  author_name text not null,
  media_url text,
  caption text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);
create index if not exists status_updates_prop_exp_idx on public.status_updates(property_id, expires_at);

create table if not exists public.status_views (
  status_id uuid not null references public.status_updates(id) on delete cascade,
  viewer_id uuid not null,
  viewer_name text,
  viewed_at timestamptz not null default now(),
  primary key (status_id, viewer_id)
);

alter table public.status_updates enable row level security;
alter table public.status_views enable row level security;

drop policy if exists members_select on public.status_updates;
create policy members_select on public.status_updates
  for select using (public.is_property_member(property_id));

drop policy if exists author_insert on public.status_updates;
create policy author_insert on public.status_updates
  for insert with check (public.is_property_member(property_id) and author_id = auth.uid());

drop policy if exists author_delete on public.status_updates;
create policy author_delete on public.status_updates
  for delete using (author_id = auth.uid());

drop policy if exists viewer_select on public.status_views;
create policy viewer_select on public.status_views
  for select using (
    exists (select 1 from public.status_updates s
            where s.id = status_id and public.is_property_member(s.property_id))
  );

drop policy if exists viewer_insert on public.status_views;
create policy viewer_insert on public.status_views
  for insert with check (
    viewer_id = auth.uid()
    and exists (select 1 from public.status_updates s
                where s.id = status_id and public.is_property_member(s.property_id))
  );
