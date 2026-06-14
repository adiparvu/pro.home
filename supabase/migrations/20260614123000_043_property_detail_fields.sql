-- Rich property profile: photo, year built, story, renovations & owners history
alter table public.properties
    add column if not exists photo_url   text,
    add column if not exists year_built  int,
    add column if not exists story       text,
    add column if not exists renovations jsonb not null default '[]'::jsonb,
    add column if not exists owners      jsonb not null default '[]'::jsonb;
