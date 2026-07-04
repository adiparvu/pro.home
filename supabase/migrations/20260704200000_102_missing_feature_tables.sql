-- 102 — create feature tables the app writes to but that were never migrated
--
-- Like paint_colors, these three features (Appliances, Photo Journal, Property
-- Value history) read/write tables that don't exist, so every add failed
-- silently. Create them to match the client models, household-scoped RLS.

-- ── appliances ──────────────────────────────────────────────────────────────
create table if not exists public.appliances (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  owner_id uuid not null,
  name text not null,
  brand text,
  model_number text,
  serial_number text,
  location text,
  category text not null default 'other',
  purchase_date text,
  warranty_until text,
  purchase_price numeric,
  notes text,
  photo_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists appliances_property_idx on public.appliances(property_id);
alter table public.appliances enable row level security;
drop policy if exists appliances_read on public.appliances;
create policy appliances_read on public.appliances
  for select using (public.has_household_access(property_id));
drop policy if exists appliances_write on public.appliances;
create policy appliances_write on public.appliances
  for all using (public.has_household_access(property_id))
  with check (public.has_household_access(property_id));

-- ── photo_journal_entries ───────────────────────────────────────────────────
create table if not exists public.photo_journal_entries (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  owner_id uuid not null,
  zone_id uuid,
  title text not null,
  caption text,
  photo_url text not null,
  taken_at timestamptz not null default now(),
  tags text[],
  created_at timestamptz not null default now()
);
create index if not exists photo_journal_property_idx on public.photo_journal_entries(property_id);
alter table public.photo_journal_entries enable row level security;
drop policy if exists photo_journal_read on public.photo_journal_entries;
create policy photo_journal_read on public.photo_journal_entries
  for select using (public.has_household_access(property_id));
drop policy if exists photo_journal_write on public.photo_journal_entries;
create policy photo_journal_write on public.photo_journal_entries
  for all using (public.has_household_access(property_id))
  with check (public.has_household_access(property_id));

-- ── property_value_entries ──────────────────────────────────────────────────
create table if not exists public.property_value_entries (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  owner_id uuid not null,
  value_amount numeric not null,
  currency text not null default 'EUR',
  source text,
  notes text,
  entered_at timestamptz not null default now()
);
create index if not exists property_value_property_idx on public.property_value_entries(property_id);
alter table public.property_value_entries enable row level security;
drop policy if exists property_value_read on public.property_value_entries;
create policy property_value_read on public.property_value_entries
  for select using (public.has_household_access(property_id));
drop policy if exists property_value_write on public.property_value_entries;
create policy property_value_write on public.property_value_entries
  for all using (public.has_household_access(property_id))
  with check (public.has_household_access(property_id));
