-- 076: Chat RLS hardening — close the critical security holes found in the chat audit.
--
-- A live-DB audit found the production project drifted from the repo migrations:
--   • direct_messages   — INSERT/SELECT/UPDATE policies were all `true` (any
--                         authenticated user could read & impersonate every DM).
--   • message_reactions — all four commands `true` AND the live table only had
--                         (id, message_id, user_name, emoji, created_at), i.e. it
--                         never received migration 051's schema, so the iOS client
--                         (which writes property_id/user_id/reactor_name) was both
--                         broken AND wide open. The table is empty, so it is safe
--                         to recreate to the schema the client expects.
--   • messages          — a single `FOR ALL` policy let ANY property member DELETE
--                         anyone's message. Split into per-command policies so reads
--                         stay member-wide but DELETE is author-only.
--   • functions         — 16 functions had a mutable search_path (advisor).
--
-- Pure security; preserves existing read/insert/edit behaviour. Idempotent.

-- ─── Identity helper (matches Swift ProfileData.preferredName) ─────────────
CREATE OR REPLACE FUNCTION public.current_user_display_name()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
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

-- ─── S1: direct_messages — only conversation parties ───────────────────────
ALTER TABLE public.direct_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "dm_insert" ON public.direct_messages;
DROP POLICY IF EXISTS "dm_select" ON public.direct_messages;
DROP POLICY IF EXISTS "dm_update" ON public.direct_messages;
DROP POLICY IF EXISTS "dm_delete" ON public.direct_messages;

CREATE POLICY "dm_insert" ON public.direct_messages
    FOR INSERT TO authenticated
    WITH CHECK (sender_name = public.current_user_display_name());

CREATE POLICY "dm_select" ON public.direct_messages
    FOR SELECT TO authenticated
    USING (sender_name    = public.current_user_display_name()
        OR recipient_name = public.current_user_display_name());

-- Either party may update their conversation (read receipts, edit, pin, react, soft-delete).
CREATE POLICY "dm_update" ON public.direct_messages
    FOR UPDATE TO authenticated
    USING (sender_name    = public.current_user_display_name()
        OR recipient_name = public.current_user_display_name())
    WITH CHECK (sender_name    = public.current_user_display_name()
        OR recipient_name = public.current_user_display_name());

CREATE POLICY "dm_delete" ON public.direct_messages
    FOR DELETE TO authenticated
    USING (sender_name = public.current_user_display_name());

-- ─── S2: message_reactions — recreate to client schema + member scope ──────
-- Live table is empty, so a clean recreate aligns it with migration 051 and the
-- iOS client (property_id / user_id / reactor_name) while securing it.
DROP TABLE IF EXISTS public.message_reactions CASCADE;

CREATE TABLE public.message_reactions (
    id           uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id   uuid         NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
    property_id  uuid         REFERENCES public.properties(id) ON DELETE CASCADE,
    user_id      uuid         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reactor_name text         NOT NULL DEFAULT '',
    emoji        text         NOT NULL,
    created_at   timestamptz  NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX uq_message_reactions_message_user
    ON public.message_reactions(message_id, user_id);
CREATE INDEX idx_message_reactions_message  ON public.message_reactions(message_id);
CREATE INDEX idx_message_reactions_property ON public.message_reactions(property_id);

ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "reactions_select_member" ON public.message_reactions
    FOR SELECT TO authenticated
    USING (public.is_property_member(property_id));

CREATE POLICY "reactions_insert_own" ON public.message_reactions
    FOR INSERT TO authenticated
    WITH CHECK (user_id = (SELECT auth.uid()) AND public.is_property_member(property_id));

CREATE POLICY "reactions_delete_own" ON public.message_reactions
    FOR DELETE TO authenticated
    USING (user_id = (SELECT auth.uid()));

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                   WHERE pubname = 'supabase_realtime' AND tablename = 'message_reactions') THEN
        EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.message_reactions';
    END IF;
EXCEPTION WHEN others THEN NULL;
END $$;

-- ─── S3: messages — reads stay member-wide, DELETE becomes author-only ──────
DROP POLICY IF EXISTS "sender_or_property_owner" ON public.messages;
DROP POLICY IF EXISTS "messages_select"      ON public.messages;
DROP POLICY IF EXISTS "messages_insert"      ON public.messages;
DROP POLICY IF EXISTS "messages_update"      ON public.messages;
DROP POLICY IF EXISTS "messages_delete_own"  ON public.messages;

CREATE POLICY "messages_select" ON public.messages
    FOR SELECT TO authenticated
    USING (sender_id = auth.uid() OR public.is_property_member(property_id));

CREATE POLICY "messages_insert" ON public.messages
    FOR INSERT TO authenticated
    WITH CHECK (sender_id = auth.uid());

CREATE POLICY "messages_update" ON public.messages
    FOR UPDATE TO authenticated
    USING (sender_id = auth.uid() OR public.is_property_member(property_id))
    WITH CHECK (sender_id = auth.uid());

CREATE POLICY "messages_delete_own" ON public.messages
    FOR DELETE TO authenticated
    USING (sender_id = auth.uid());

-- ─── S5: pin a fixed search_path on every public function ──────────────────
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.prokind = 'f'
          AND pg_get_userbyid(p.proowner) = current_user
          -- skip functions installed by extensions (e.g. citext); we don't own them
          AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
          AND NOT EXISTS (
              SELECT 1 FROM unnest(coalesce(p.proconfig, '{}'::text[])) c
              WHERE c LIKE 'search_path=%'
          )
    LOOP
        EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', r.sig);
    END LOOP;
END $$;
