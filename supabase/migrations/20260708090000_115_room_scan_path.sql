-- Plans & 3D rebuild, phase A: rooms can carry a 3D scan.
-- The .usdz lives in the private `documents` bucket; this is its object
-- path (signed on display, never a public URL).
alter table public.rooms add column if not exists scan_path text;
comment on column public.rooms.scan_path is
  'Storage object path (documents bucket) of the room''s RoomPlan .usdz scan; null = no scan yet.';
