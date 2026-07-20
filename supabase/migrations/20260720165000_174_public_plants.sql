-- 174: proiecția publică a plantelor pentru etichetele QR (IMG_8728:
-- "oricine să poată scana codul și să vadă informațiile").
-- Oglindită din aplicație când proprietarul folosește cardul Etichetă QR
-- — opt-in prin actul de a genera/afișa eticheta, ca la public_items.

create table if not exists public.public_plants (
  id uuid primary key default gen_random_uuid(),
  plant_uuid uuid not null unique,
  name text not null,
  species text,
  emoji text,
  location text,
  property_name text,
  planted_at timestamptz,
  watering_interval_days int,
  user_id uuid,
  updated_at timestamptz not null default now()
);

alter table public.public_plants enable row level security;

-- Pagina publică (worker, cheie anon) citește liber — asta e menirea ei.
create policy "public_plants_read" on public.public_plants
  for select to anon, authenticated using (true);

-- Scriu doar proprietarii, doar pe rândurile lor.
create policy "public_plants_insert" on public.public_plants
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "public_plants_update" on public.public_plants
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "public_plants_delete" on public.public_plants
  for delete to authenticated using (user_id = (select auth.uid()));

grant select on public.public_plants to anon;
grant select, insert, update, delete on public.public_plants to authenticated;
