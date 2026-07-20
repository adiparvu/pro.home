-- Paint color pages (IMG_8628): honest usage metadata — when the color
-- was last used, and whether/where a leftover can still sits around the
-- house. Both user-entered, both nullable; absent stays absent in UI.
alter table public.paint_colors
  add column if not exists last_used_at date,
  add column if not exists leftover_note text;
