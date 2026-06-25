-- 051: message_reactions — persist emoji reactions on group chat messages

CREATE TABLE IF NOT EXISTS public.message_reactions (
    id           uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id   uuid         NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
    property_id  uuid         REFERENCES public.properties(id) ON DELETE CASCADE,
    user_id      uuid         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reactor_name text         NOT NULL DEFAULT '',
    emoji        text         NOT NULL,
    created_at   timestamptz  NOT NULL DEFAULT now()
);

-- One reaction per user per message (toggle: remove + re-insert to change emoji)
CREATE UNIQUE INDEX IF NOT EXISTS uq_message_reactions_message_user
    ON public.message_reactions(message_id, user_id);

CREATE INDEX IF NOT EXISTS idx_message_reactions_message
    ON public.message_reactions(message_id);

CREATE INDEX IF NOT EXISTS idx_message_reactions_property
    ON public.message_reactions(property_id);

ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

-- Property members can see all reactions for their property
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'message_reactions' AND policyname = 'reactions_select_member'
    ) THEN
        EXECUTE 'CREATE POLICY "reactions_select_member" ON public.message_reactions
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM public.property_members pm
                    WHERE pm.property_id = message_reactions.property_id
                      AND pm.user_id = (SELECT auth.uid())
                      AND pm.status = ''active''
                )
            )';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'message_reactions' AND policyname = 'reactions_insert_own'
    ) THEN
        EXECUTE 'CREATE POLICY "reactions_insert_own" ON public.message_reactions
            FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()))';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'message_reactions' AND policyname = 'reactions_delete_own'
    ) THEN
        EXECUTE 'CREATE POLICY "reactions_delete_own" ON public.message_reactions
            FOR DELETE USING (user_id = (SELECT auth.uid()))';
    END IF;
END $$;

-- Realtime: broadcast reaction changes so all participants see live updates
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'message_reactions'
    ) THEN
        EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.message_reactions';
    END IF;
EXCEPTION WHEN others THEN
    NULL;
END $$;
