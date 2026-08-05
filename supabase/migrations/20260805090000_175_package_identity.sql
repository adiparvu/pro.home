-- Delivery identity (IMG_9298): one parcel accumulates every reference the
-- retailer's and courier's emails mention (order number, AWB…) instead of
-- spawning a new card per number. Applied live 2026-08-05 as
-- `packages_identity_columns`; this file is the repo's record of it.
alter table public.packages
  add column if not exists aliases jsonb not null default '[]'::jsonb,
  add column if not exists merchant text,
  add column if not exists source_emails jsonb not null default '[]'::jsonb;
