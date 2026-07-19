-- Domain sale inquiries (xparvu.com holding page contact form).
-- The public page posts with the publishable key: anon may INSERT only
-- (bounded by CHECK constraints), and can never read anything back;
-- signed-in app users (the owner) read the inbox.
create table if not exists public.domain_inquiries (
  id uuid primary key default gen_random_uuid(),
  name text check (char_length(name) <= 200),
  email text not null check (char_length(email) between 3 and 320),
  message text not null check (char_length(message) between 1 and 4000),
  created_at timestamptz not null default now()
);

alter table public.domain_inquiries enable row level security;

drop policy if exists "domain_inquiries_insert_anon" on public.domain_inquiries;
create policy "domain_inquiries_insert_anon" on public.domain_inquiries
  for insert to anon with check (true);

drop policy if exists "domain_inquiries_select_auth" on public.domain_inquiries;
create policy "domain_inquiries_select_auth" on public.domain_inquiries
  for select to authenticated using (true);

grant insert on public.domain_inquiries to anon;
grant select on public.domain_inquiries to authenticated;
