-- 066: poll votes for in-chat polls (poll itself stored as a message with attachment_type='poll')
CREATE TABLE IF NOT EXISTS public.message_poll_votes (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id   uuid        NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
    property_id  uuid        REFERENCES public.properties(id) ON DELETE CASCADE,
    user_id      uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    voter_name   text        NOT NULL DEFAULT '',
    option_index int         NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_poll_votes_msg_user_opt ON public.message_poll_votes(message_id, user_id, option_index);
CREATE INDEX IF NOT EXISTS idx_poll_votes_message ON public.message_poll_votes(message_id);
ALTER TABLE public.message_poll_votes ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='message_poll_votes' AND policyname='poll_votes_select_member') THEN
    EXECUTE 'CREATE POLICY "poll_votes_select_member" ON public.message_poll_votes FOR SELECT USING (EXISTS (SELECT 1 FROM public.property_members pm WHERE pm.property_id = message_poll_votes.property_id AND pm.user_id = (SELECT auth.uid()) AND pm.status = ''active''))';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='message_poll_votes' AND policyname='poll_votes_insert_own') THEN
    EXECUTE 'CREATE POLICY "poll_votes_insert_own" ON public.message_poll_votes FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()))';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='message_poll_votes' AND policyname='poll_votes_delete_own') THEN
    EXECUTE 'CREATE POLICY "poll_votes_delete_own" ON public.message_poll_votes FOR DELETE USING (user_id = (SELECT auth.uid()))';
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='message_poll_votes') THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.message_poll_votes';
  END IF;
EXCEPTION WHEN others THEN NULL;
END $$;
