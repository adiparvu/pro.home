-- 050: Fix direct_messages RLS (security) + add delete policies
--
-- Migration 049 used WITH CHECK (true) / USING (true) — any authenticated
-- user could read ALL DMs and impersonate anyone as sender.  This migration
-- replaces those policies with proper per-user restrictions.
--
-- Also adds a delete policy on direct_messages so senders can delete their
-- own messages, and a delete policy on the group messages table (if it exists).

-- ─── Helper: map auth.uid() → the user's display name ─────────────────────
-- Matches Swift's ProfileData.preferredName:
--   COALESCE(display_name, full_name, email-prefix)
CREATE OR REPLACE FUNCTION public.current_user_display_name()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        NULLIF(p.display_name, ''),
        NULLIF(p.full_name, ''),
        split_part(p.email::text, '@', 1)
    )
    FROM public.profiles p
    WHERE p.id = auth.uid()
    LIMIT 1;
$$;

-- ─── Replace permissive direct_messages policies ───────────────────────────

DROP POLICY IF EXISTS "dm_insert" ON public.direct_messages;
DROP POLICY IF EXISTS "dm_select" ON public.direct_messages;

-- INSERT: sender_name must equal the authenticated user's display name
CREATE POLICY "dm_insert" ON public.direct_messages
    FOR INSERT TO authenticated
    WITH CHECK (sender_name = public.current_user_display_name());

-- SELECT: only parties to the conversation can read their DMs
CREATE POLICY "dm_select" ON public.direct_messages
    FOR SELECT TO authenticated
    USING (
        sender_name    = public.current_user_display_name()
        OR
        recipient_name = public.current_user_display_name()
    );

-- DELETE: only the original sender can delete their own DMs
CREATE POLICY "dm_delete" ON public.direct_messages
    FOR DELETE TO authenticated
    USING (sender_name = public.current_user_display_name());

-- ─── Delete policy for group chat messages (sender_id-based) ──────────────

DO $$ BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'messages'
    ) THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_policies
            WHERE tablename = 'messages' AND policyname = 'messages_delete_own'
        ) THEN
            EXECUTE 'CREATE POLICY "messages_delete_own" ON public.messages
                FOR DELETE TO authenticated
                USING (sender_id = auth.uid())';
        END IF;
    END IF;
END $$;
