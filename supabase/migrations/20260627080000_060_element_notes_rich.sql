-- 060: Rich notes — checklist + photos on element notes.
alter table public.element_notes
  add column if not exists checklist jsonb not null default '[]'::jsonb,
  add column if not exists photo_urls text[] not null default '{}';
