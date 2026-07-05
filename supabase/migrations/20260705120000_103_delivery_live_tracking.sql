-- 103 — live courier tracking for deliveries (aggregator-driven)
--
-- Extends `packages` so a delivery can be tracked live through a tracking
-- aggregator (Ship24 / AfterShip). The app registers a tracking number with the
-- aggregator, which then pushes status events to a webhook Edge Function; that
-- function writes the normalized status + full checkpoint timeline back here, so
-- the user follows every parcel inside PRVIO instead of the courier's own app.
--
-- These columns are provider-agnostic: `tracker_id` is just the aggregator's
-- opaque id, `live_status` is a normalized milestone, and `checkpoints` is the
-- event timeline. Swapping aggregators never touches this schema.

alter table public.packages
  add column if not exists tracker_id        text,         -- aggregator tracker id
  add column if not exists courier_code       text,        -- normalized courier slug (e.g. "dhl", "fan-courier")
  add column if not exists live_status        text,        -- pending | info_received | in_transit | out_for_delivery | available_for_pickup | delivered | exception | failed_attempt | expired
  add column if not exists estimated_delivery timestamptz, -- aggregator ETA, when known
  add column if not exists checkpoints        jsonb not null default '[]'::jsonb, -- [{ time, status, message, location }]
  add column if not exists last_event_at      timestamptz, -- timestamp of the most recent checkpoint
  add column if not exists last_synced_at     timestamptz, -- last time the aggregator updated this row
  add column if not exists tracking_enabled   boolean not null default true; -- user can pause live tracking

-- Webhooks look packages up by the aggregator's tracker id.
create index if not exists packages_tracker_id_idx on public.packages(tracker_id);

-- Fast lookup of parcels still being tracked (for re-registration / sweeps).
create index if not exists packages_live_status_idx on public.packages(live_status)
  where live_status is not null and live_status <> 'delivered';

comment on column public.packages.tracker_id is 'Opaque tracking id from the aggregator (Ship24/AfterShip). Null until registered.';
comment on column public.packages.checkpoints is 'Ordered event timeline: [{ time, status, message, location }]. Written by the tracking webhook.';
