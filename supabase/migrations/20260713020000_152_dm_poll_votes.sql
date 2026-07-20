-- 152: RSVP/votes for DM event messages — the direct_messages counterpart of
-- message_poll_votes (066). DMs had no vote storage, so event bubbles in a
-- 1-on-1 thread couldn't offer Going / Can't go; this mirrors the group
-- table's shape, uniqueness, RLS (property membership — the same visibility
-- model the DM table itself uses) and realtime publication.
CREATE TABLE IF NOT EXISTS public.dm_poll_votes (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id   uuid        NOT NULL REFERENCES public.direct_messages(id) ON DELETE CASCADE,
    property_id  uuid        REFERENCES public.properties(id) ON DELETE CASCADE,
    user_id      uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    voter_name   text        NOT NULL DEFAULT '',
    option_index int         NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_dm_poll_votes_msg_user_opt ON public.dm_poll_votes(message_id, user_id, option_index);
CREATE INDEX IF NOT EXISTS idx_dm_poll_votes_message ON public.dm_poll_votes(message_id);
ALTER TABLE public.dm_poll_votes ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='dm_poll_votes' AND policyname='dm_poll_votes_select_member') THEN
    EXECUTE 'CREATE POLICY "dm_poll_votes_select_member" ON public.dm_poll_votes FOR SELECT USING (EXISTS (SELECT 1 FROM public.property_members pm WHERE pm.property_id = dm_poll_votes.property_id AND pm.user_id = (SELECT auth.uid()) AND pm.status = ''active''))';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='dm_poll_votes' AND policyname='dm_poll_votes_insert_own') THEN
    EXECUTE 'CREATE POLICY "dm_poll_votes_insert_own" ON public.dm_poll_votes FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()))';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='dm_poll_votes' AND policyname='dm_poll_votes_delete_own') THEN
    EXECUTE 'CREATE POLICY "dm_poll_votes_delete_own" ON public.dm_poll_votes FOR DELETE USING (user_id = (SELECT auth.uid()))';
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='dm_poll_votes') THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.dm_poll_votes';
  END IF;
EXCEPTION WHEN others THEN NULL;
END $$;
