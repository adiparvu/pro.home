-- 154: living sensor history (Smart Control R4).
-- iot_events grows a second writer: the signed-in app mirrors HomeKit
-- indoor-climate readings (event = 'reading', throttled client-side to one
-- point per sensor per 30 minutes) so HomeKit sensors accrue the same
-- history as webhook-fed ones. Owners may insert ONLY their own rows; the
-- iot-event edge function keeps writing with the service role as before.

drop policy if exists "insert own iot events" on public.iot_events;
create policy "insert own iot events"
  on public.iot_events
  for insert
  with check (auth.uid() = user_id);

-- Per-sensor history reads: (user, sensor, newest-first) — the exact shape
-- of the history chart's query and the mirror's freshness check.
create index if not exists iot_events_user_sensor_time_idx
  on public.iot_events (user_id, sensor_id, created_at desc);
