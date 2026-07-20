-- Space avatar vs background separation (IMG_8638/8639 follow-up):
-- photo_url remains the immersive BACKDROP of the space page; avatar_url
-- is the small identity disc shown in the hero and on list rows.
-- Nullable — spaces without either keep the icon disc.
alter table public.property_zones
  add column if not exists avatar_url text;
