# PRVIO Plant OS — specification (user vision, 2026-07-08)

The plants module grows from a watering journal into a botanical operating
system: every plant is a living page backed by an encyclopedia, numeric care
requirements compared against real sensors, a health knowledge base with
guided/AI diagnosis, a full care timeline, per-plant automations riding the
existing IoT engine, and an explainable 0–100 health score.

Source vision: the user's six levels (general info · botanical profile ·
care requirements · health · history · smart automations) plus the
encyclopedia and the Plant Health Score. Honesty rules apply throughout: no
invented sensor readings, no fabricated AI percentages, no button that
claims an action it doesn't perform.

## What already exists (build on, don't duplicate)

- `plants` table + `Plant` model: name, species, location, watering interval,
  last watered, health status, notes, emoji, one photo.
- `PlantSpeciesCatalog` (in-app species picker) — becomes the seed skeleton.
- IoT hub: controllers, sensors (auto-discovery), automations
  (threshold → notification / task / webhook / phone alert) — Level 6 reuses
  this engine instead of building a second one.
- `plantCare` Live Activity (Dynamic Island program, phases A–F).
- Photo upload pipeline (private bucket, signed URLs), FormKit, GuideSheet.

## Phase P1 — Data model + Level 1 (general info)

- Migration: extend `plants` with nickname, latin_name, family, genus,
  cultivar, origin, climate_zone, toxic_cats/dogs/kids (bool), placement
  (indoor/outdoor/both).
- New `plant_photos` (id, plant_id, url, taken_at, note) — the evolution
  album; main photo stays on the plant row.
- Rebuilt add/edit form on FormKit (sectioned) and a restructured plant page
  with six surfaces: Overview · Botanical profile · Care · Health · History ·
  Automations. Liquid Glass, RO+EN, Dynamic Type.

## Phase P2 — Encyclopedia + Level 2 (botanical profile)

- New `plant_species` knowledge base: identification (common name, latin,
  synonyms, family, genus, species), natural habitat (origin, altitude,
  native temperature/humidity, forest/climate type), characteristics
  (max height/width, growth rate, lifespan, evergreen, flowering period,
  fruiting, fragrance), leaves (size, shape, colour, texture, variegation,
  gloss), roots (shallow/deep/rhizome/tuber), propagation guide, pruning
  guide, seasonal checklist, annual calendar, FAQ, myths, curiosities,
  sources/bibliography.
- Species picker links a plant to its encyclopedia page; the page renders
  every populated section (missing data simply doesn't render — never
  placeholder-invented).
- Seed: start with ~50 popular indoor/outdoor species fully populated
  (hand-curated, sources cited in the seed migration); the structure scales
  to hundreds. Growing the corpus is content work, ongoing.

## Phase P3 — Level 3 (numeric care requirements + live comparison)

- Per species: light in lux (min/ideal/max), temperature bands
  (ideal/accepted/dangerous/critical), air humidity (ideal/accepted),
  soil pH (min/ideal/max), substrate mix with percentages
  (peat/coco/perlite/bark/sand), watering per season (+ "top X cm dry"
  rule), fertilization (type, NPK, frequency, months, winter pause),
  repotting (interval, pot diameter step, max, best period).
- Plant ↔ sensor binding: attach IoT hub sensors (lux/temp/humidity) to a
  plant. With a sensor bound, the care page compares live: "Planta primește
  doar 380 lux (ideal 1.200)". Without sensors it shows requirements only —
  no fake readings.

## Phase P4 — Level 4 (health: ailments, pests, diagnosis)

- New `plant_ailments` knowledge base (diseases + pests): symptoms,
  photo references, treatment, prevention; linked to species
  (susceptibility). Seed ~40 common entries, structure scales to 200+.
- Guided diagnosis: symptom checklist → decision tree over the knowledge
  base → ranked matches with treatment/prevention steps. Fully offline,
  fully honest.
- AI photo diagnosis: photograph → ARIA vision pipeline. GATED on verifying
  the backing model accepts images; confidence shown ONLY when the model
  returns one. If vision isn't available, the guided path is the diagnosis
  story — no fabricated "92%".

## Phase P5 — Level 5 (complete history timeline)

- New `plant_events` (plant_id, kind: watered/fertilized/repotted/sprayed/
  treated/pruned/photo/note, at, details) + quick actions on the plant page
  ("Am udat" → event + last_watered update).
- Timeline view (grouped by month, icons per kind) as the History surface;
  photo events interleave from `plant_photos`.

## Phase P6 — Level 6 (automations) + Plant Health Score

- Per-plant automations reuse the IoT automation engine: bound sensor +
  threshold → notification / task / webhook / phone alert, tagged with the
  plant so its page lists its own rules. Pump/humidifier/LED control goes
  through the existing actuator layer (relay on a controller) or an
  outbound webhook (Homebridge/Shortcuts). Native HomeKit is explicitly a
  separate future phase — not claimed until built.
- Plant Health Score 0–100, explainable: computed ONLY from real inputs —
  watering discipline vs interval (events), care events recency,
  bound-sensor readings vs species bands, photo recency. Each factor shows
  its contribution and a concrete recommendation; missing factors shrink
  the denominator instead of inventing data. Shown on the plant page,
  widgets and the watch glance.

## Sequencing & estimates

P1 (1 build) → P2 (2 builds, seed-heavy) → P3 (1–2) → P5 (1, small — can
run before P4) → P4 (2) → P6 (2). Each phase lands green on CI, RO+EN,
production-ready; specs in this file are the contract.
