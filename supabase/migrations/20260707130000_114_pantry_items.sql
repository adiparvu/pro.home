-- 114: The pantry — real household stock. Receipt scans grow it (the scanner
-- upserts by normalized name and adds quantities), consumption shrinks it
-- from the pantry page. One row per product per property; the normalized
-- name is the merge key so "LAPTE ZUZU 1.5%" and "Lapte" land on one stock.

create table if not exists public.pantry_items (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  name text not null,
  normalized_name text not null,
  quantity numeric not null default 0 check (quantity >= 0),
  unit text not null default 'buc' check (unit in ('buc','kg','l')),
  category text not null default 'food',
  -- Low-stock threshold; null = no alert for this product.
  min_quantity numeric,
  emoji text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- The merge key: one stock row per product per household.
create unique index if not exists pantry_items_prop_norm_idx
  on public.pantry_items (property_id, normalized_name);

alter table public.pantry_items enable row level security;
drop policy if exists pantry_items_household on public.pantry_items;
create policy pantry_items_household on public.pantry_items
  for all
  using (public.has_household_access(property_id))
  with check (public.has_household_access(property_id));
