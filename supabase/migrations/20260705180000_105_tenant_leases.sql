-- 105 — tenant lease details (professional tenant form)
--
-- Tenants live in family_members (role = 'tenant'); this table holds the
-- lease/contract details the dedicated tenant form captures — kept separate so
-- family_members stays a lean people table and a tenant can have a lease
-- history (one active row per member for now).

create table if not exists public.tenant_leases (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties(id) on delete cascade,
  member_id    uuid not null references public.family_members(id) on delete cascade,
  lease_start  date,
  lease_end    date,
  monthly_rent numeric,
  currency     text not null default 'EUR',
  deposit      numeric,
  payment_day  int check (payment_day between 1 and 31),
  occupants    int,
  notes        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists tenant_leases_property_idx on public.tenant_leases(property_id);
create index if not exists tenant_leases_member_idx on public.tenant_leases(member_id);

alter table public.tenant_leases enable row level security;

drop policy if exists tenant_leases_read on public.tenant_leases;
create policy tenant_leases_read on public.tenant_leases
  for select using (public.has_household_access(property_id));

drop policy if exists tenant_leases_insert on public.tenant_leases;
create policy tenant_leases_insert on public.tenant_leases
  for insert with check (public.has_household_access(property_id));

drop policy if exists tenant_leases_update on public.tenant_leases;
create policy tenant_leases_update on public.tenant_leases
  for update using (public.has_household_access(property_id));

drop policy if exists tenant_leases_delete on public.tenant_leases;
create policy tenant_leases_delete on public.tenant_leases
  for delete using (public.has_household_access(property_id));
