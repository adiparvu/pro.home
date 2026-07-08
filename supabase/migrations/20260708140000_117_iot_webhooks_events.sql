-- 117: locked-phone IoT alerts.
-- iot_webhooks: one secret per account; the controller firmware (or the
-- app's "Phone Alert" automation) POSTs sensor events to the iot-event
-- edge function with ?token=<secret>. iot_events: the persisted event log
-- (written by the edge function with the service role; owners read).

create table if not exists public.iot_webhooks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade unique,
  secret text not null unique,
  created_at timestamptz not null default now()
);

alter table public.iot_webhooks enable row level security;

drop policy if exists "own iot webhook" on public.iot_webhooks;
create policy "own iot webhook"
  on public.iot_webhooks
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public.iot_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  sensor_id text,
  name text,
  type text,
  value double precision,
  unit text,
  zone text,
  display text,
  event text not null default 'alert',
  created_at timestamptz not null default now()
);

create index if not exists iot_events_user_time_idx
  on public.iot_events (user_id, created_at desc);

alter table public.iot_events enable row level security;

drop policy if exists "read own iot events" on public.iot_events;
create policy "read own iot events"
  on public.iot_events
  for select
  using (auth.uid() = user_id);
