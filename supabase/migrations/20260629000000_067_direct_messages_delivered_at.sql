-- 067: DM delivery receipts + the missing UPDATE policy
--
-- Adds `delivered_at` so the chat can show 3-state ticks
-- (sent → delivered → read), mirroring WhatsApp.
--
-- It also adds the UPDATE RLS policy that direct_messages never had:
-- migration 049 created only INSERT/SELECT, 050 added DELETE. With RLS
-- enabled and no UPDATE policy, every UPDATE (read_at, pin, mark, edit,
-- reactions, delete-for-all tombstone) was silently denied — it changed
-- 0 rows and the client swallowed the result, so receipts and edits never
-- persisted to the database or synced to the other party.

alter table public.direct_messages
  add column if not exists delivered_at timestamptz;

-- Either party to the conversation may update a message:
--   sender    → edit, pin, mark, delete-for-all, reactions
--   recipient → delivered_at, read_at, reactions
drop policy if exists "dm_update" on public.direct_messages;
create policy "dm_update" on public.direct_messages
    for update to authenticated
    using (
        sender_name    = public.current_user_display_name()
        or
        recipient_name = public.current_user_display_name()
    )
    with check (
        sender_name    = public.current_user_display_name()
        or
        recipient_name = public.current_user_display_name()
    );
