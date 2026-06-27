-- 059: Free-form tags on property elements.
alter table public.property_elements
  add column if not exists tags text[] not null default '{}';
