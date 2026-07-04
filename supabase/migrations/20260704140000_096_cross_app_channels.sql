-- 096 — cross-app messaging gateway
--
-- One inbound channel per property: a secret token that external services
-- (Shortcuts automations, Zapier, IFTTT, anything that can POST) present to
-- the cross-app-inbox edge function to drop a message into the house chat.
-- The edge function reads via the service role; RLS covers the app's own
-- management UI (household reads, owner/partner manage).

create table if not exists public.cross_app_channels (
  property_id uuid primary key references public.properties(id) on delete cascade,
  token uuid not null default gen_random_uuid(),
  enabled boolean not null default true,
  notify_requests boolean not null default true,
  created_by uuid not null,
  created_at timestamptz not null default now()
);

alter table public.cross_app_channels enable row level security;

drop policy if exists cross_app_select on public.cross_app_channels;
create policy cross_app_select on public.cross_app_channels
  for select using (public.has_household_access(property_id));

drop policy if exists cross_app_insert on public.cross_app_channels;
create policy cross_app_insert on public.cross_app_channels
  for insert with check (public.member_role(property_id) in ('owner','partner'));

drop policy if exists cross_app_update on public.cross_app_channels;
create policy cross_app_update on public.cross_app_channels
  for update using (public.member_role(property_id) in ('owner','partner'))
  with check (public.member_role(property_id) in ('owner','partner'));

drop policy if exists cross_app_delete on public.cross_app_channels;
create policy cross_app_delete on public.cross_app_channels
  for delete using (public.member_role(property_id) in ('owner','partner'));
