-- 084: Phase 4 (A) — server-side enforcement of disappearing messages.
--
-- Disappearing messages were view-only: ChatDisappearStore hid old messages in
-- the UI, but the rows stayed in the database forever, so "disappeared" content
-- was still retrievable. This adds a per-message expires_at (stamped by the
-- client at send time from the conversation's TTL) and extends the pg_cron sweep
-- to actually delete expired messages, in both the group and DM tables.

ALTER TABLE public.messages
    ADD COLUMN IF NOT EXISTS expires_at timestamptz;
ALTER TABLE public.direct_messages
    ADD COLUMN IF NOT EXISTS expires_at timestamptz;

-- Partial indexes so the sweep only scans rows that actually expire.
CREATE INDEX IF NOT EXISTS idx_messages_expires_at
    ON public.messages(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_dm_expires_at
    ON public.direct_messages(expires_at) WHERE expires_at IS NOT NULL;

-- Extend the existing 15-min sweep to delete expired messages too.
CREATE OR REPLACE FUNCTION public.cleanup_expired_chat_ephemera()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    DELETE FROM public.status_updates   WHERE expires_at < now();
    DELETE FROM public.live_locations   WHERE expires_at < now();
    DELETE FROM public.messages         WHERE expires_at IS NOT NULL AND expires_at < now();
    DELETE FROM public.direct_messages  WHERE expires_at IS NOT NULL AND expires_at < now();
END;
$$;
