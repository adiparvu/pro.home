-- 083: Phase 4 — pg_cron sweep for expired ephemeral chat data.
--
-- status_updates (stories) and live_locations both carry an expires_at, but
-- nothing ever deletes expired rows, so they accumulate forever and expired
-- stories/locations keep being returned by queries that forget to filter on
-- expires_at. This adds a cleanup function and schedules it every 15 minutes,
-- following the existing prv-* cron pattern.

CREATE OR REPLACE FUNCTION public.cleanup_expired_chat_ephemera()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    DELETE FROM public.status_updates  WHERE expires_at < now();
    DELETE FROM public.live_locations  WHERE expires_at < now();
END;
$$;

-- Schedule (pg_cron upserts by name, so re-running is safe).
SELECT cron.schedule(
    'prv-chat-ephemera-sweep',
    '*/15 * * * *',
    'select public.cleanup_expired_chat_ephemera()'
);
