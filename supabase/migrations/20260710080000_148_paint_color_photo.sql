-- 148 — paint_colors.photo_url
--
-- The rebuilt "Culoare nouă" form gains an optional photo (the painted wall
-- or the tin label), uploaded to the public `documents` bucket like the
-- photo journal. Add the column the iOS client now writes; existing rows
-- keep NULL and render exactly as before.

alter table public.paint_colors add column if not exists photo_url text;
