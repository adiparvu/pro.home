-- 061: Server-backed global automations (migrated off UserDefaults).
create table if not exists public.property_automations (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  name text not null default '',
  trigger_icon text not null default '',
  trigger_label text not null default '',
  condition_icon text not null default '',
  condition_label text not null default '',
  action_icon text not null default '',
  action_label text not null default '',
  is_active boolean not null default true,
  color_hex text not null default '#0A84FF',
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists idx_property_automations_property on public.property_automations(property_id);

alter table public.property_automations enable row level security;
drop policy if exists property_automations_select on public.property_automations;
create policy property_automations_select on public.property_automations for select using (is_property_member(property_id));
drop policy if exists property_automations_insert on public.property_automations;
create policy property_automations_insert on public.property_automations for insert with check (is_property_member(property_id));
drop policy if exists property_automations_update on public.property_automations;
create policy property_automations_update on public.property_automations for update using (is_property_member(property_id)) with check (is_property_member(property_id));
drop policy if exists property_automations_delete on public.property_automations;
create policy property_automations_delete on public.property_automations for delete using (is_property_member(property_id));
