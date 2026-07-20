-- Contractor avatars (train 1147): contractors WITHOUT a PRVIO account can
-- carry their own photo; matched accounts keep showing the account's avatar.
-- Nullable, user-set from the add/edit forms; absent stays absent in UI.
alter table public.contractors
  add column if not exists photo_url text;
