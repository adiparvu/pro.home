-- 070: APNs device tokens for native iOS push
--
-- Web Push uses push_subscriptions (VAPID). Native iOS push needs the APNs
-- device token, stored here. The send-chat-push edge function reads these to
-- deliver pushes for notifications whose module = 'chat' (and can be reused
-- for any module later).

create table if not exists public.device_tokens (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null references auth.users(id) on delete cascade,
  token        text        not null unique,
  platform     text        not null default 'ios',
  environment  text        not null default 'production',  -- 'sandbox' | 'production'
  app_version  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists idx_device_tokens_user on public.device_tokens(user_id);

alter table public.device_tokens enable row level security;

drop policy if exists "device_tokens_manage_own" on public.device_tokens;
create policy "device_tokens_manage_own"
  on public.device_tokens
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
