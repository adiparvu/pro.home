-- MetricKit telemetry (applied live 2026-08-05 as `app_metrics_table`; this
-- file is the repo's record). Real launch/hang/memory numbers from the
-- family's devices, one row per payload, written by the reporting user.
create table public.app_metrics (
  id uuid primary key default gen_random_uuid(),
  property_id uuid references public.properties(id) on delete cascade,
  user_id uuid not null,
  kind text not null,
  app_version text,
  os_version text,
  device_model text,
  payload jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.app_metrics enable row level security;
create policy app_metrics_insert_own on public.app_metrics
  for insert to authenticated
  with check (user_id = auth.uid());
create policy app_metrics_select_member on public.app_metrics
  for select to authenticated
  using (user_id = auth.uid()
         or (property_id is not null and has_household_access(property_id)));
create index app_metrics_property_created on public.app_metrics (property_id, created_at desc);
