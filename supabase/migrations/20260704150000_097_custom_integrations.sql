-- 097 — named custom integrations
--
-- "Add anything" integrations: each external service the household connects
-- (a webhook, a Zapier zap, an IoT bridge, a home server…) gets its own named
-- row with a dedicated secret token. Tokens are individually toggleable and
-- revocable (delete the row) without touching the property's shared channel
-- token, and last_used_at shows when the service last delivered a message.
-- The cross-app-inbox edge function accepts these tokens alongside the shared
-- cross_app_channels token; the channel row stays the per-property master
-- switch. RLS: household reads, owner/partner manage.

create table if not exists public.custom_integrations (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  name text not null,
  icon text not null default 'puzzlepiece.extension.fill',
  color text not null default '#5B8AF5',
  token uuid not null unique default gen_random_uuid(),
  enabled boolean not null default true,
  last_used_at timestamptz,
  created_by uuid not null,
  created_at timestamptz not null default now()
);

create index if not exists custom_integrations_property_idx
  on public.custom_integrations(property_id);

alter table public.custom_integrations enable row level security;

drop policy if exists custom_integrations_select on public.custom_integrations;
create policy custom_integrations_select on public.custom_integrations
  for select using (public.has_household_access(property_id));

drop policy if exists custom_integrations_insert on public.custom_integrations;
create policy custom_integrations_insert on public.custom_integrations
  for insert with check (public.member_role(property_id) in ('owner','partner'));

drop policy if exists custom_integrations_update on public.custom_integrations;
create policy custom_integrations_update on public.custom_integrations
  for update using (public.member_role(property_id) in ('owner','partner'))
  with check (public.member_role(property_id) in ('owner','partner'));

drop policy if exists custom_integrations_delete on public.custom_integrations;
create policy custom_integrations_delete on public.custom_integrations
  for delete using (public.member_role(property_id) in ('owner','partner'));
