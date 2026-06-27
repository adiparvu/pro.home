-- 053: Per-element cover photo + automation (electric gate / powered) metadata.
alter table public.property_elements
  add column if not exists cover_photo_url text,
  add column if not exists is_electric boolean not null default false,
  add column if not exists automation_system text;
