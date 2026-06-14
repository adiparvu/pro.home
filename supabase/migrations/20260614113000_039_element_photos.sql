-- Digital Property Twin — object photos
-- Stores an ordered list of photo URLs (Supabase Storage public URLs) per object.

alter table public.property_elements
    add column if not exists photo_urls jsonb not null default '[]'::jsonb;
