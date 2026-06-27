-- 055: Per-element notes (lockable). Locked notes store an AES-GCM encrypted
-- blob in `body` (encrypted client-side via NoteLockManager).
create table if not exists public.element_notes (
  id uuid primary key default gen_random_uuid(),
  element_id uuid not null references public.property_elements(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  body text not null default '',
  is_locked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_element_notes_element on public.element_notes(element_id);

alter table public.element_notes enable row level security;

drop policy if exists element_notes_select on public.element_notes;
create policy element_notes_select on public.element_notes
  for select using (is_property_member(property_id));

drop policy if exists element_notes_insert on public.element_notes;
create policy element_notes_insert on public.element_notes
  for insert with check (is_property_member(property_id));

drop policy if exists element_notes_update on public.element_notes;
create policy element_notes_update on public.element_notes
  for update using (is_property_member(property_id)) with check (is_property_member(property_id));

drop policy if exists element_notes_delete on public.element_notes;
create policy element_notes_delete on public.element_notes
  for delete using (is_property_member(property_id));
