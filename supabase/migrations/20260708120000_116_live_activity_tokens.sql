-- 116: ActivityKit push tokens for server-updated Live Activities.
-- The app registers a token per started (live-tracked) delivery activity;
-- the track-webhook edge function reads them by tracker id and sends
-- apns-push-type: liveactivity updates so the Dynamic Island moves while
-- the phone is locked. Rows are owned and managed by their user; the edge
-- function reads them with the service role.

create table if not exists public.live_activity_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  activity_kind text not null default 'delivery',
  activity_id text not null unique,
  tracker_id text,
  token text not null,
  environment text not null default 'production',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists live_activity_tokens_tracker_idx
  on public.live_activity_tokens (tracker_id);

alter table public.live_activity_tokens enable row level security;

drop policy if exists "own live activity tokens" on public.live_activity_tokens;
create policy "own live activity tokens"
  on public.live_activity_tokens
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
