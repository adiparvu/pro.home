-- 056: Per-element automations (phase 1: reminder rules that schedule a local
-- notification and optionally create a maintenance task).
create table if not exists public.element_automations (
  id uuid primary key default gen_random_uuid(),
  element_id uuid not null references public.property_elements(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  name text not null default '',
  trigger_type text not null default 'periodic',  -- periodic | once | warranty
  interval_months int,
  next_run date,
  creates_task boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_element_automations_element on public.element_automations(element_id);

alter table public.element_automations enable row level security;

drop policy if exists element_automations_select on public.element_automations;
create policy element_automations_select on public.element_automations
  for select using (is_property_member(property_id));
drop policy if exists element_automations_insert on public.element_automations;
create policy element_automations_insert on public.element_automations
  for insert with check (is_property_member(property_id));
drop policy if exists element_automations_update on public.element_automations;
create policy element_automations_update on public.element_automations
  for update using (is_property_member(property_id)) with check (is_property_member(property_id));
drop policy if exists element_automations_delete on public.element_automations;
create policy element_automations_delete on public.element_automations
  for delete using (is_property_member(property_id));
