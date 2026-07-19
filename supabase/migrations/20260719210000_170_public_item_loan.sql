-- Public item page: live loan status ("împrumutat lui X din data Y").
-- Synced by the app on every loan-out / return, not just on card save.
alter table public.public_items
  add column if not exists loaned_to text,
  add column if not exists loaned_at timestamptz;
