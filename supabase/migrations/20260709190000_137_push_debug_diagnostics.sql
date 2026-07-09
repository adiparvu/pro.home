-- 137: Temporary diagnostics table to capture why APNs device-token
-- registration fails on TestFlight builds (the on-device error is silent in
-- Release). The app writes registration outcomes here so we can read the exact
-- reason. Safe to drop once push delivery is confirmed working.
create table if not exists public.push_debug (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  event text not null,
  detail text,
  app_version text,
  created_at timestamptz not null default now()
);

alter table public.push_debug enable row level security;

drop policy if exists push_debug_insert on public.push_debug;
create policy push_debug_insert on public.push_debug
  for insert to authenticated with check (true);

drop policy if exists push_debug_select_own on public.push_debug;
create policy push_debug_select_own on public.push_debug
  for select to authenticated using (user_id = auth.uid());
