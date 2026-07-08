-- 118: instant chat push.
-- Until now send-chat-push was written to be invoked by a webhook or cron,
-- but nothing ever invoked it - a chat message never buzzed a locked phone.
-- This trigger calls the function over pg_net the moment a chat notification
-- row lands, so delivery is instant and needs no dashboard configuration.
--
-- Secret handling (this repo is public): the shared secret lives ONLY in
-- Supabase Vault (inserted out-of-band, never in a migration). The trigger
-- reads it from the vault; the edge function fetches the same value through
-- chat_push_secret(), an RPC executable only by service_role, and compares.

create extension if not exists pg_net;

-- The edge function's side of the handshake. SECURITY DEFINER so it can read
-- the vault; executable only with the service role key.
create or replace function public.chat_push_secret()
returns text
language sql
security definer
set search_path = ''
as $$
  select decrypted_secret
  from vault.decrypted_secrets
  where name = 'chat_push_webhook'
  limit 1;
$$;

revoke all on function public.chat_push_secret() from public;
revoke all on function public.chat_push_secret() from anon;
revoke all on function public.chat_push_secret() from authenticated;
grant execute on function public.chat_push_secret() to service_role;

-- Fire-and-forget HTTP nudge; the function itself claims and sends whatever
-- is unpushed, so bursts of inserts just cause a few no-op calls.
create or replace function public.notify_chat_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  secret text;
begin
  select decrypted_secret into secret
  from vault.decrypted_secrets
  where name = 'chat_push_webhook'
  limit 1;

  if secret is null then
    return new; -- not armed yet: never block the insert
  end if;

  perform net.http_post(
    url     := 'https://kwcanenheihuylaymwsl.supabase.co/functions/v1/send-chat-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', secret
    ),
    body    := '{}'::jsonb
  );
  return new;
exception when others then
  -- Push delivery is best-effort; the message insert must never fail
  -- because the nudge did.
  return new;
end;
$$;

drop trigger if exists trg_notify_chat_push on public.notifications;
create trigger trg_notify_chat_push
  after insert on public.notifications
  for each row
  when (new.module = 'chat')
  execute function public.notify_chat_push();
