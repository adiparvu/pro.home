-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 017: Web Push subscriptions
-- ═══════════════════════════════════════════════════════════════════════════
-- Stores browser push subscriptions per user. Dispatch happens through the
-- web app's /api/push/dispatch route using VAPID keys from the environment.

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now()
);

alter table public.push_subscriptions enable row level security;

create policy "Users manage own push subscriptions"
  on public.push_subscriptions
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists idx_push_subscriptions_user
  on public.push_subscriptions(user_id);
