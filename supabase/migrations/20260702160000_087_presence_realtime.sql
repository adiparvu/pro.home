-- 087 — stream presence over realtime
--
-- Add the presence table to the supabase_realtime publication so a member
-- coming online flips live for everyone in the conversation, instead of
-- waiting for the next 45s heartbeat/poll. The client keeps the poll too — it
-- provides the "went offline" decay that a stopped heartbeat can't push.

alter publication supabase_realtime add table public.presence;
