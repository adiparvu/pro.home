-- Public item page v2 (lost & found): the projection grows the owner's
-- email, the ITEM's own pinned coordinates (for the map + navigation
-- links), and the owner's chosen app icon (uploaded preview) so the page
-- badge mirrors their PRVIO identity. All optional — the owner opts in
-- per field from the Lost & Found card.
alter table public.public_items
  add column if not exists owner_email text,
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists app_icon_url text;
