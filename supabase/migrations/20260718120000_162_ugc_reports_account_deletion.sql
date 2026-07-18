-- 162: App Store compliance — UGC message reporting + account-deletion
--      hardening.
--
-- (a) content_reports (Guideline 1.2): a signed-in member reports a chat
--     message. WRITE-ONLY from the API: reporters INSERT their own report;
--     no select/update/delete policies exist, so reports are readable only
--     with the service role (the moderation side). The body snapshot is
--     captured at report time so moderation sees what was reported even if
--     the message is later edited or deleted.
--
-- (b) delete_my_account: the RPC was applied live on 2026-07-07
--     (delete_my_account_rpc) but never landed in the repo — this file
--     records the LIVE definition verbatim so the repo is truth again,
--     and adds the missing grant hardening: SECURITY DEFINER functions in
--     public are callable by every role by default; the auth.uid() guard
--     already fails anonymous calls, but the explicit revoke/grant makes
--     the contract visible and closes the anon surface entirely.

create table if not exists public.content_reports (
    id            uuid primary key default gen_random_uuid(),
    property_id   uuid,
    message_id    uuid not null,
    message_kind  text not null check (message_kind in ('group', 'dm')),
    reported_by   uuid not null references auth.users(id) on delete cascade,
    reason        text not null check (char_length(reason) <= 200),
    body_snapshot text,
    created_at    timestamptz not null default now()
);

alter table public.content_reports enable row level security;

drop policy if exists content_reports_insert_own on public.content_reports;
create policy content_reports_insert_own
    on public.content_reports
    for insert to authenticated
    with check (reported_by = auth.uid());

-- The live definition (2026-07-07), recorded verbatim: property-creator
-- cascade wipe, authored-content deletes inside other households, then a
-- best-effort auth.users delete that must not roll back the data wipe.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  -- Properties this user created: FK cascades remove all property-scoped
  -- data (zones, elements, tasks, records, documents, plants, appliances,
  -- supplies, receipts, journal, paint colors, valuations, inventory...).
  delete from public.properties where creator_id = uid;

  -- Rows this user authored inside OTHER households (their content leaves,
  -- the household stays).
  delete from public.maintenance_tasks  where created_by = uid;
  delete from public.financial_records  where created_by = uid;
  delete from public.contractors        where created_by = uid;
  delete from public.messages           where sender_id  = uid;
  delete from public.direct_messages    where sender_id  = uid;
  delete from public.status_updates     where author_id  = uid;
  delete from public.message_reads      where user_id = uid;
  delete from public.message_reactions  where user_id = uid;
  delete from public.aria_messages      where user_id = uid;
  delete from public.audit_logs         where user_id = uid;
  delete from public.notifications      where user_id = uid;
  delete from public.device_tokens      where user_id = uid;
  delete from public.push_subscriptions where user_id = uid;
  delete from public.chat_user_prefs    where user_id = uid;
  delete from public.presence           where user_id = uid;
  delete from public.property_members   where user_id = uid;

  delete from public.profiles where id = uid;

  -- Best effort on the auth record itself: a failure here (privilege
  -- differences between environments) must not roll back the data wipe.
  begin
    delete from auth.users where id = uid;
  exception when others then
    null;
  end;
end;
$function$;

revoke all on function public.delete_my_account() from public;
revoke all on function public.delete_my_account() from anon;
grant execute on function public.delete_my_account() to authenticated;
