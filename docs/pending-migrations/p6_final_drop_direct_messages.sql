-- ============================================================================
-- P6 FINAL — retirement of direct_messages. PREPARED, NOT YET APPLIED.
--
-- PRECONDITION (the only reason this file sits here instead of in the
-- migration history): EVERY family device runs build 1201+ (the first build
-- whose client never touches direct_messages). Applying this while any
-- device still runs ≤1199 destroys that device's DMs; applying it while the
-- mirrors still fire is impossible anyway (msg_mirror_insert would error on
-- the missing table and BLOCK message sends) — which is why the mirror
-- triggers drop in the same transaction, before the table.
--
-- Apply with: supabase apply_migration chat_p6_final_drop_direct_messages
-- ============================================================================

-- 1) The mirrors stop first: messages↔direct_messages must not fire against
--    a table that is about to leave (msg_mirror_insert on messages would
--    otherwise error INSIDE every message send).
drop trigger if exists msg_mirror_insert_trg on public.messages;
drop trigger if exists msg_mirror_update_trg on public.messages;
drop trigger if exists dm_mirror_insert_trg on public.direct_messages;
drop trigger if exists dm_mirror_update_trg on public.direct_messages;
drop trigger if exists dm_mirror_delete_trg on public.direct_messages;
drop function if exists public.msg_mirror_insert();
drop function if exists public.msg_mirror_update();
drop function if exists public.dm_mirror_insert();
drop function if exists public.dm_mirror_update();
drop function if exists public.dm_mirror_delete();
drop function if exists public.reaction_mirror_back();
drop function if exists public.receipt_mirror_back();

-- 2) Server-side consumers stop referencing the table.
create or replace function public.cleanup_expired_chat_ephemera()
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
    delete from public.status_updates   where expires_at < now();
    delete from public.live_locations   where expires_at < now();
    delete from public.messages         where expires_at is not null and expires_at < now();
end;
$function$;

-- delete_my_account: identical body minus the direct_messages line (DM rows
-- authored by the leaver now live only in messages, already covered).
-- (Full body re-stated at apply time from the current definition — regenerate
-- it then rather than trusting this snapshot if the function has changed.)

-- 3) The kill-switch leaves WITH the table — a flag that can only break the
--    fleet must not survive as a trap. The DM branch of messages_select
--    stops consulting it.
drop policy if exists messages_select on public.messages;
create policy messages_select on public.messages for select using (
  ((conversation_id is null) and ((sender_id = auth.uid())
     or ((group_id is null) and has_family_access(property_id))
     or ((group_id is not null) and is_chat_group_member(group_id, auth.uid()))))
  or ((conversation_id is not null) and is_conversation_member(conversation_id, auth.uid()))
);
drop function if exists public.dm_unified_read_enabled();
drop table if exists public.chat_rollout;

-- 4) The table itself, last.
drop table if exists public.direct_messages;
