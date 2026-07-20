-- 156: Realtime Authorization was implicitly denying ALL broadcast and
-- presence traffic — realtime.messages had RLS enabled with ZERO policies,
-- so every typing/recording signal and the dm_new/msg_new delivery ping
-- (all broadcast) were dropped server-side. That is why the in-thread typing
-- indicator never appeared and why live messages only sometimes arrived
-- (postgres_changes alone, which the direct_messages SELECT policy withholds
-- per-subscriber).
--
-- Every PRVIO realtime user is an authenticated household member, so grant
-- authenticated users full use of Realtime broadcast + presence. Realtime
-- checks SELECT (to receive) and INSERT (to send) on realtime.messages.
CREATE POLICY "prvio_authenticated_realtime_receive"
    ON realtime.messages FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "prvio_authenticated_realtime_send"
    ON realtime.messages FOR INSERT
    TO authenticated
    WITH CHECK (true);
