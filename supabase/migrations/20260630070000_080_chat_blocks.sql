-- 080: S7 — make "Block" actually enforced server-side.
--
-- Today blocking lives only in UserDefaults: a blocked person can still INSERT
-- direct_messages to you; you just don't render them. This table records blocks
-- and the dm_insert policy is tightened so a blocked sender is rejected by the
-- database. Identity is name-based to match the existing DM model (sender_name /
-- recipient_name); it migrates to user ids with S8.

CREATE TABLE IF NOT EXISTS public.chat_blocks (
    blocker_name text        NOT NULL,                                  -- the user doing the blocking
    blocked_name text        NOT NULL,                                  -- the user being blocked
    property_id  uuid        NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_name, blocked_name, property_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_blocks_pair
    ON public.chat_blocks(blocker_name, blocked_name, property_id);

ALTER TABLE public.chat_blocks ENABLE ROW LEVEL SECURITY;

-- A user manages and sees only the blocks they created.
DROP POLICY IF EXISTS blocks_select ON public.chat_blocks;
CREATE POLICY blocks_select ON public.chat_blocks
    FOR SELECT TO authenticated
    USING (blocker_name = public.current_user_display_name());

DROP POLICY IF EXISTS blocks_write ON public.chat_blocks;
CREATE POLICY blocks_write ON public.chat_blocks
    FOR ALL TO authenticated
    USING (blocker_name = public.current_user_display_name())
    WITH CHECK (blocker_name = public.current_user_display_name());

-- Tighten DM insert (extends migration 076 dm_insert): you still must be the
-- sender, AND the recipient must not have blocked you.
DROP POLICY IF EXISTS "dm_insert" ON public.direct_messages;
CREATE POLICY "dm_insert" ON public.direct_messages
    FOR INSERT TO authenticated
    WITH CHECK (
        sender_name = public.current_user_display_name()
        AND NOT EXISTS (
            SELECT 1 FROM public.chat_blocks b
            WHERE b.blocker_name = direct_messages.recipient_name
              AND b.blocked_name = direct_messages.sender_name
              AND b.property_id  = direct_messages.property_id
        )
    );
