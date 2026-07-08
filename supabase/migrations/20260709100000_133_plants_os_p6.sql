-- 133: Plant OS, phase P6 — per-plant automations + the explainable Health Score.
--
-- Two additions, both additive and safe to re-run:
--
--   1. `plant_automations` — the durable, household-synced record of a
--      per-plant automation rule. This is the plant ↔ automation TAG the phase
--      calls for: each row belongs to exactly one plant (plant_id) and one
--      property (property_id, for RLS). A rule reuses the existing IoT hub
--      automation vocabulary — a bound sensor (sensor_ref, the same stable
--      installation-local identity P3's plant_sensors already uses), a metric,
--      a comparison, a threshold, and one action. The client materialises the
--      active rows whose sensor is present on THIS device into the real IoT
--      automation engine (IoTService), which is what actually evaluates and
--      fires them on each sensor poll — this table never runs anything itself.
--
--      HONESTY NOTE: the "device" action never claims native HomeKit. It rides
--      the existing actuator layer (a real relay on a controller, addressed by
--      actuator_ref) or an outbound webhook (Homebridge/Shortcuts) — both of
--      which the engine can actually reach. A rule whose sensor is not present
--      on the current device is listed but explicitly not evaluated here.
--
--   2. `plants.health_score` / `plants.health_score_at` — the last computed
--      Plant Health Score (0–100) and when it was computed. The score is
--      derived ONLY from real inputs on the plant page (watering discipline vs
--      interval, care-event recency, bound-sensor readings vs species bands,
--      photo recency); missing factors shrink the denominator rather than
--      inventing data. Persisting it lets widgets, the watch glance and other
--      household devices read the value without recomputing — and the
--      timestamp keeps the surfaced number honest ("as of …").

-- ── plants: persisted Health Score (nullable — nil = not computed yet) ─────
alter table public.plants
  add column if not exists health_score    int,
  add column if not exists health_score_at timestamptz;

alter table public.plants
  drop constraint if exists plants_health_score_range;
alter table public.plants
  add constraint plants_health_score_range
  check (health_score is null or (health_score >= 0 and health_score <= 100));

-- ── plant_automations: per-plant automation rules (plant ↔ automation tag) ─
create table if not exists public.plant_automations (
  id uuid primary key default gen_random_uuid(),
  plant_id uuid not null references public.plants(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  name text not null,
  -- The bound sensor this rule watches. Same identity as plant_sensors.sensor_ref
  -- ("{deviceId-uuid}:{remoteId}", see IoTSensor.stableRef): sensors live in the
  -- client-side IoT hub, so a rule can only be EVALUATED on a device that knows
  -- the sensor. Elsewhere the row is shown but not fired (never a fake reading).
  sensor_ref text not null,
  metric text not null check (metric in ('light','temperature','humidity')),
  -- Reuses the IoT engine's comparison/threshold vocabulary.
  comparison text not null check (comparison in ('above','below')),
  threshold numeric not null,
  -- Reuses the IoT engine's action set. 'device' rides the real actuator layer
  -- (actuator_ref) or a webhook — never a HomeKit claim.
  action text not null check (action in ('notify','task','webhook','phone_alert','device')),
  -- Webhook URL, task title, or free text depending on the action; nullable.
  action_payload text,
  -- For the 'device' action driving a real relay through the actuator layer:
  -- the actuator's installation-local identity ("{deviceId-uuid}:{remoteId}").
  -- nil when 'device' is delivered purely via action_payload's webhook.
  actuator_ref text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_plant_automations_plant
  on public.plant_automations (plant_id);
create index if not exists idx_plant_automations_property
  on public.plant_automations (property_id);

alter table public.plant_automations enable row level security;

-- Same visibility as the plant it belongs to: any member of the property.
drop policy if exists plant_automations_access on public.plant_automations;
create policy plant_automations_access on public.plant_automations
  for all to authenticated
  using (public.is_property_member(property_id))
  with check (public.is_property_member(property_id));
