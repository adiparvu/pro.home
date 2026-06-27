-- 054: Mark property elements as favorites.
alter table public.property_elements
  add column if not exists is_favorite boolean not null default false;
create index if not exists idx_property_elements_favorite
  on public.property_elements(property_id) where is_favorite;
