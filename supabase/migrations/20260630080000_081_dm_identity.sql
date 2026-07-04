-- 081: S8 — give direct messages a stable identity (not just display names).
--
-- PREPARED, NOT YET APPLIED. Apply when the Supabase MCP is reconnected.
--
-- Today direct_messages identifies parties only by sender_name / recipient_name
-- (text). Two members sharing a name collapse into one conversation, and a
-- client can trivially spoof another person by sending their name. This adds
-- stable id columns so identity no longer rests on a display string.
--
-- Identity model for this app:
--   • the SENDER is always the authenticated user  -> sender_id = auth.users.id
--     (verifiable in RLS via auth.uid(); this is the real anti-spoofing fix)
--   • each party also maps to a family_members row  -> *_member_id (stable
--     contact identity, because most chat members are contacts, not auth users)
--
-- ROLLOUT (safe, staged — names keep working the whole time):
--   1. (this migration) add nullable id columns + indexes; tighten dm_insert to
--      verify sender_id WHEN the client provides it. Old name-only inserts still
--      work, so nothing breaks during the transition.
--   2. iOS: DirectMessageService stamps sender_id / sender_member_id /
--      recipient_member_id on send, and loads/filters conversations by the
--      member-id pair (falling back to names when ids are absent).
--   3. backfill historical rows (map names -> family_members.id), then add FKs
--      and make sender_id NOT NULL once every client writes it.
--
-- No hard FKs yet: the live direct_messages table has already drifted from its
-- original migration, so columns are added defensively and FKs are deferred to
-- step 3 after a verified backfill.

ALTER TABLE public.direct_messages
    ADD COLUMN IF NOT EXISTS sender_id           uuid,   -- auth.users.id of the sender
    ADD COLUMN IF NOT EXISTS sender_member_id    uuid,   -- family_members.id of the sender
    ADD COLUMN IF NOT EXISTS recipient_member_id uuid;   -- family_members.id of the recipient

-- Conversation lookup by stable member-id pair (both directions).
CREATE INDEX IF NOT EXISTS idx_dm_member_pair
    ON public.direct_messages(sender_member_id, recipient_member_id);
CREATE INDEX IF NOT EXISTS idx_dm_sender_id
    ON public.direct_messages(sender_id);

-- Tighten dm_insert (extends migration 080): still must be the sender by name and
-- not blocked, AND — once the client supplies sender_id — it must equal auth.uid().
-- sender_id IS NULL stays allowed so older clients keep working until step 3.
DROP POLICY IF EXISTS "dm_insert" ON public.direct_messages;
CREATE POLICY "dm_insert" ON public.direct_messages
    FOR INSERT TO authenticated
    WITH CHECK (
        sender_name = public.current_user_display_name()
        AND (sender_id IS NULL OR sender_id = auth.uid())
        AND NOT EXISTS (
            SELECT 1 FROM public.chat_blocks b
            WHERE b.blocker_name = direct_messages.recipient_name
              AND b.blocked_name = direct_messages.sender_name
        )
    );
