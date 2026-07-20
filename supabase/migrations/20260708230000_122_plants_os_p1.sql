-- 122: Plant OS, phase P1 — general info + photo album.
--
-- Plants grow from a watering journal toward a botanical record. This adds
-- the "general information" fields (identity, taxonomy, origin, toxicity,
-- placement) and a photo album table for tracking a plant's evolution over
-- time. Everything is additive and nullable, so existing rows/clients keep
-- working; the encyclopedia + care/health/automation levels build on P2+.

alter table public.plants
  add column if not exists nickname text,
  add column if not exists latin_name text,
  add column if not exists botanical_family text,
  add column if not exists genus text,
  add column if not exists cultivar text,
  add column if not exists origin text,
  add column if not exists climate_zone text,
  add column if not exists toxic_cats boolean not null default false,
  add column if not exists toxic_dogs boolean not null default false,
  add column if not exists toxic_kids boolean not null default false,
  add column if not exists placement text;   -- indoor / outdoor / both

-- The evolution album. The main photo stays on plants.photo_url; these are
-- the timeline of growth shots.
create table if not exists public.plant_photos (
  id uuid primary key default gen_random_uuid(),
  plant_id uuid not null references public.plants(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  url text not null,
  note text,
  taken_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists idx_plant_photos_plant on public.plant_photos (plant_id, taken_at desc);

alter table public.plant_photos enable row level security;

-- Same visibility as the plant: any member of the property can read/write.
drop policy if exists plant_photos_access on public.plant_photos;
create policy plant_photos_access on public.plant_photos
  for all to authenticated
  using (public.is_property_member(property_id))
  with check (public.is_property_member(property_id));

-- Private bucket for the album photos, member-scoped by property folder
-- (path convention {property_id}/{plant_id}/{uuid}.jpg), signed URLs on read.
insert into storage.buckets (id, name, public)
values ('plant-media', 'plant-media', false)
on conflict (id) do nothing;

drop policy if exists plant_media_select_member on storage.objects;
create policy plant_media_select_member on storage.objects
  for select to authenticated
  using (bucket_id = 'plant-media' and public.is_property_member(((storage.foldername(name))[1])::uuid));

drop policy if exists plant_media_insert_member on storage.objects;
create policy plant_media_insert_member on storage.objects
  for insert to authenticated
  with check (bucket_id = 'plant-media' and public.is_property_member(((storage.foldername(name))[1])::uuid));

drop policy if exists plant_media_delete_member on storage.objects;
create policy plant_media_delete_member on storage.objects
  for delete to authenticated
  using (bucket_id = 'plant-media' and public.is_property_member(((storage.foldername(name))[1])::uuid));
