-- 107: Contact profile fields the iOS app already sends when adding a
-- contact (Add manually / device-contacts invite). Their absence made every
-- contact add fail with "Could not find the 'social_links' column".
alter table public.family_members
  add column if not exists birthday date,
  add column if not exists social_links jsonb not null default '[]'::jsonb;
