-- 058: Allow zones to be drawn directly on the static aerial photo via a
-- normalized (0–1) polygon, since the MapKit map was removed.
alter table public.property_zones
  add column if not exists image_polygon jsonb;
