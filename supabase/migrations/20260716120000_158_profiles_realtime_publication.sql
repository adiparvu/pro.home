-- 158: `profiles` was never added to the realtime publication, so the app's
-- avatar-sync channel (MemberDirectory → pg_changes on public.profiles) was
-- rejected on every join with "Unable to subscribe to changes with given
-- parameters" — each rejection cycling ~5 retries × 10s of join traffic and
-- repeating after every socket reconnect (seen live in the Build 1036 flight
-- recorder). Rows are still RLS-filtered per subscriber, so membership
-- boundaries are unchanged; this only lets the replication stream carry the
-- table at all.
ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
