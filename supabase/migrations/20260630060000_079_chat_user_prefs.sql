-- 079: A2 — per-user conversation preferences, synced across devices.
--
-- Pin / mute / archive and the "clear conversation" cutoff currently live only
-- in UserDefaults on one device (ConversationClearStore, pin/mute stores), so
-- they are lost on reinstall and never sync. This table backs them per user.
--
-- conv_id is a stable conversation key chosen by the client:
--   'group'                    → the property-wide main group chat
--   a chat_groups UUID (text)  → a Communities group
--   the DM peer's display name → a 1:1 conversation
-- Kept as text so all three conversation kinds share one table.

CREATE TABLE IF NOT EXISTS public.chat_user_prefs (
    user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    conv_id     text        NOT NULL,
    property_id uuid        REFERENCES public.properties(id) ON DELETE CASCADE,
    pinned      boolean     NOT NULL DEFAULT false,
    muted       boolean     NOT NULL DEFAULT false,
    archived    boolean     NOT NULL DEFAULT false,
    -- "clear conversation" high-water mark: hide messages at/*before* this time.
    cleared_at  timestamptz,
    updated_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, conv_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_user_prefs_user ON public.chat_user_prefs(user_id);

ALTER TABLE public.chat_user_prefs ENABLE ROW LEVEL SECURITY;

-- A user sees and manages only their own preferences.
DROP POLICY IF EXISTS prefs_rw ON public.chat_user_prefs;
CREATE POLICY prefs_rw ON public.chat_user_prefs
    FOR ALL TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Realtime so a pin/mute on one device reflects on the others.
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                   WHERE pubname='supabase_realtime' AND tablename='chat_user_prefs') THEN
        EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_user_prefs';
    END IF;
EXCEPTION WHEN others THEN NULL;
END $$;
