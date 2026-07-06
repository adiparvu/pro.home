-- 113: Real disappearing messages — the setting itself syncs.
--
-- Migration 084 gave messages/direct_messages an expires_at and a pg_cron
-- sweep, and senders stamp outgoing rows. But the TTL lived in each
-- device's UserDefaults: the other participant never learned it, so their
-- messages never expired and their view never hid anything. This table
-- makes the conversation's TTL shared state: any participant sets it,
-- every client reads it, every sender stamps with it.
--
-- conv_key is identical for all participants: 'group' for the family chat,
-- the community group's UUID, or 'dm:<nameA>|<nameB>' with names sorted.

create table if not exists public.chat_disappear_settings (
  property_id uuid not null references public.properties(id) on delete cascade,
  conv_key    text not null,
  ttl_seconds bigint not null default 0,
  updated_by  uuid,
  updated_at  timestamptz not null default now(),
  primary key (property_id, conv_key)
);

alter table public.chat_disappear_settings enable row level security;

drop policy if exists chat_disappear_select on public.chat_disappear_settings;
create policy chat_disappear_select on public.chat_disappear_settings
  for select using (public.is_property_member(property_id));

drop policy if exists chat_disappear_insert on public.chat_disappear_settings;
create policy chat_disappear_insert on public.chat_disappear_settings
  for insert with check (public.is_property_member(property_id));

drop policy if exists chat_disappear_update on public.chat_disappear_settings;
create policy chat_disappear_update on public.chat_disappear_settings
  for update using (public.is_property_member(property_id));

drop policy if exists chat_disappear_delete on public.chat_disappear_settings;
create policy chat_disappear_delete on public.chat_disappear_settings
  for delete using (public.is_property_member(property_id));

create or replace function public.touch_chat_disappear()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_touch_chat_disappear on public.chat_disappear_settings;
create trigger trg_touch_chat_disappear
  before update on public.chat_disappear_settings
  for each row execute function public.touch_chat_disappear();

-- Live propagation: the peer's client learns the new TTL without a reload.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'chat_disappear_settings'
  ) then
    execute 'alter publication supabase_realtime add table public.chat_disappear_settings';
  end if;

  -- Regression fix: migration 049 added direct_messages to the publication,
  -- but the live publication no longer contained it — DM postgres_changes
  -- events were silently not firing. Re-add it.
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'direct_messages'
  ) then
    execute 'alter publication supabase_realtime add table public.direct_messages';
  end if;
end $$;
