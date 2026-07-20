-- 128: Plant OS, phase P5 — complete history timeline.
--
-- A plant's care history becomes a first-class, append-only log. `plant_events`
-- records the real actions a caretaker took — watered / fertilized / repotted /
-- sprayed / treated / pruned / note — each stamped with when it happened. The
-- plant page renders these, grouped by month, as the History surface, with
-- photo events (from plant_photos, migration 122) interleaved for a full
-- timeline. Everything is additive; nothing else reads it, so older clients are
-- unaffected.
--
-- Honesty rule: an event is written ONLY when the user performs the action
-- (e.g. the "Am udat" quick action logs a `watered` event AND updates
-- plants.last_watered_at) — never fabricated.

create table if not exists public.plant_events (
  id          uuid primary key default gen_random_uuid(),
  plant_id    uuid not null references public.plants(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  kind        text not null,           -- watered/fertilized/repotted/sprayed/
                                        -- treated/pruned/note
  details     jsonb,                    -- small, flat context ({"note": "..."})
  at          timestamptz not null default now(),
  created_at  timestamptz not null default now()
);

create index if not exists idx_plant_events_plant
  on public.plant_events (plant_id, at desc);

alter table public.plant_events enable row level security;

-- Property-scoped visibility, exactly like plant_photos (migration 122): plants
-- are property-scoped, so any member of the plant's property can read/write its
-- events. NOT parent-inherited — the property_id column carries the scope
-- directly and is enforced with the shared membership predicate.
drop policy if exists plant_events_access on public.plant_events;
create policy plant_events_access on public.plant_events
  for all to authenticated
  using (public.is_property_member(property_id))
  with check (public.is_property_member(property_id));
