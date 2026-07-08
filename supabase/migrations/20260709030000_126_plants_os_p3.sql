-- 126: Plant OS, phase P3 — numeric care requirements + live sensor comparison.
--
-- Two additions:
--   1. Care columns on the shared `plant_species` catalog: light (lux), the
--      temperature comfort/danger bands, air humidity, soil pH, substrate mix,
--      per-season watering, fertilising and repotting. All nullable.
--   2. `plant_sensors` — a property-scoped binding between a plant and a real
--      IoT hub sensor, so the care page can compare a species' requirement
--      against a live reading (light/temperature/humidity).
--
-- HONESTY NOTE: the seeded care numbers below are hand-curated general
-- horticultural guidance for these very common species. Only values we are
-- confident of are set; everything uncertain (precise pH, substrate recipes,
-- exact NPK ratios, pot ceilings) is deliberately left NULL, and the UI shows
-- only populated fields. Light lux figures are approximate conversions of the
-- well-established light categories (low-light / bright-indirect / full-sun),
-- not per-cultivar instrument readings, and should be read as ranges.

-- ── Care columns (all nullable, additive) ────────────────────────────────
alter table public.plant_species
  add column if not exists light_lux_min        int,
  add column if not exists light_lux_ideal      int,
  add column if not exists light_lux_max        int,
  add column if not exists temp_ideal_min       numeric,
  add column if not exists temp_ideal_max       numeric,
  add column if not exists temp_accepted_min    numeric,
  add column if not exists temp_accepted_max    numeric,
  add column if not exists temp_danger_low      numeric,
  add column if not exists temp_danger_high     numeric,
  add column if not exists humidity_ideal_min   int,
  add column if not exists humidity_ideal_max   int,
  add column if not exists humidity_accepted_min int,
  add column if not exists humidity_accepted_max int,
  add column if not exists ph_min               numeric,
  add column if not exists ph_ideal             numeric,
  add column if not exists ph_max               numeric,
  add column if not exists substrate_mix        jsonb,   -- {"coco":40,"perlite":30,"bark":30}
  add column if not exists water_spring         text,
  add column if not exists water_summer         text,
  add column if not exists water_autumn         text,
  add column if not exists water_winter         text,
  add column if not exists water_topcm          int,     -- "let the top X cm dry out"
  add column if not exists fertilizer_type      text,
  add column if not exists fertilizer_npk       text,
  add column if not exists fertilizer_freq      text,
  add column if not exists fertilizer_months    text[],
  add column if not exists fertilizer_winter_pause boolean,
  add column if not exists repot_interval       text,
  add column if not exists repot_pot_step_cm    int,
  add column if not exists repot_pot_max_cm      int,
  add column if not exists repot_period         text;

-- ── plant_sensors: plant ↔ IoT sensor binding ────────────────────────────
--
-- sensor_ref is the STABLE identity of a sensor in the IoT hub. Sensors are
-- persisted client-side (UserDefaults JSON), not in a synced table, and the
-- poller matches a sensor by (deviceId, remoteId) — so the durable key is the
-- tuple "{deviceId-uuid}:{remoteId}" (see IoTSensor.stableRef). The row is
-- property-scoped for RLS; if the bound sensor is not present on the device
-- opening the page, the UI shows requirements only and never a fake reading.
create table if not exists public.plant_sensors (
  id uuid primary key default gen_random_uuid(),
  plant_id uuid not null references public.plants(id) on delete cascade,
  property_id uuid not null references public.properties(id) on delete cascade,
  sensor_ref text not null,
  metric text not null check (metric in ('light','temperature','humidity')),
  created_at timestamptz not null default now(),
  unique (plant_id, metric)
);

create index if not exists idx_plant_sensors_plant on public.plant_sensors (plant_id);

alter table public.plant_sensors enable row level security;

-- Same visibility as the plant it belongs to: any member of the property.
drop policy if exists plant_sensors_access on public.plant_sensors;
create policy plant_sensors_access on public.plant_sensors
  for all to authenticated
  using (public.is_property_member(property_id))
  with check (public.is_property_member(property_id));

-- ── Curated care seed ─────────────────────────────────────────────────────
-- UPDATE by slug so it targets the P2-seeded rows and is safe to re-run.
-- Only confident values are set; uncertain fields stay NULL by omission.

update public.plant_species set
  light_lux_min = 1000, light_lux_ideal = 2500, light_lux_max = 20000,
  temp_ideal_min = 18, temp_ideal_max = 27, temp_accepted_min = 15, temp_accepted_max = 30,
  temp_danger_low = 10, temp_danger_high = 35,
  humidity_ideal_min = 60, humidity_ideal_max = 80, humidity_accepted_min = 40, humidity_accepted_max = 90,
  ph_min = 5.5, ph_ideal = 6.0, ph_max = 7.0,
  substrate_mix = '{"coco":40,"perlite":30,"bark":30}'::jsonb,
  water_spring = 'Water when the top 2–3 cm of soil feels dry.',
  water_summer = 'Peak growth; water when the top 2–3 cm dries out, more often in heat.',
  water_autumn = 'Let more of the soil dry between waterings as growth slows.',
  water_winter = 'Water sparingly, only when the top few cm are dry.',
  water_topcm = 3,
  fertilizer_type = 'Balanced liquid houseplant fertiliser',
  fertilizer_freq = 'Every 2–4 weeks in spring and summer',
  fertilizer_months = ARRAY['April','May','June','July','August','September'],
  fertilizer_winter_pause = true,
  repot_interval = 'Every 1–2 years, when rootbound',
  repot_pot_step_cm = 3, repot_period = 'Spring'
where slug = 'monstera-deliciosa';

update public.plant_species set
  light_lux_min = 1500, light_lux_ideal = 3000, light_lux_max = 20000,
  temp_ideal_min = 18, temp_ideal_max = 27, temp_accepted_min = 15, temp_accepted_max = 30,
  temp_danger_low = 12, temp_danger_high = 35,
  humidity_ideal_min = 40, humidity_ideal_max = 60, humidity_accepted_min = 30, humidity_accepted_max = 70,
  ph_min = 5.5, ph_ideal = 6.0, ph_max = 7.0,
  water_spring = 'Water when the top 3 cm feels dry; keep it in a stable, bright spot.',
  water_summer = 'Water when the top 3 cm dries; avoid letting it wilt or sit wet.',
  water_autumn = 'Reduce watering as light levels drop.',
  water_winter = 'Water sparingly; keep away from cold draughts and radiators.',
  water_topcm = 3,
  fertilizer_type = 'Balanced liquid houseplant fertiliser',
  fertilizer_freq = 'Monthly in spring and summer',
  fertilizer_months = ARRAY['April','May','June','July','August','September'],
  fertilizer_winter_pause = true,
  repot_interval = 'Every 1–2 years while young',
  repot_pot_step_cm = 3, repot_period = 'Spring'
where slug = 'ficus-lyrata';

update public.plant_species set
  light_lux_min = 500, light_lux_ideal = 2000, light_lux_max = 30000,
  temp_ideal_min = 18, temp_ideal_max = 27, temp_accepted_min = 13, temp_accepted_max = 30,
  temp_danger_low = 10, temp_danger_high = 38,
  humidity_ideal_min = 30, humidity_ideal_max = 50, humidity_accepted_min = 20, humidity_accepted_max = 60,
  ph_min = 6.0, ph_ideal = 6.5, ph_max = 7.5,
  substrate_mix = '{"potting_soil":60,"perlite":20,"sand":20}'::jsonb,
  water_spring = 'Let the soil dry out fully, then water; roughly every 2–3 weeks.',
  water_summer = 'Water only when completely dry; it stores water and tolerates drought.',
  water_autumn = 'Water less as temperatures fall.',
  water_winter = 'Water rarely — about once a month; overwatering rots the rhizome.',
  fertilizer_type = 'Low-nitrogen cactus/succulent feed',
  fertilizer_freq = 'Once or twice over spring and summer',
  fertilizer_months = ARRAY['May','July'],
  fertilizer_winter_pause = true,
  repot_interval = 'Every 2–3 years, or when it splits the pot',
  repot_pot_step_cm = 3, repot_period = 'Spring'
where slug = 'sansevieria-trifasciata';

update public.plant_species set
  light_lux_min = 500, light_lux_ideal = 1500, light_lux_max = 15000,
  temp_ideal_min = 18, temp_ideal_max = 27, temp_accepted_min = 15, temp_accepted_max = 30,
  temp_danger_low = 10, temp_danger_high = 35,
  humidity_ideal_min = 50, humidity_ideal_max = 70, humidity_accepted_min = 40, humidity_accepted_max = 90,
  ph_min = 5.5, ph_ideal = 6.0, ph_max = 7.0,
  substrate_mix = '{"coco":40,"perlite":30,"bark":30}'::jsonb,
  water_spring = 'Water when the top 2–3 cm dries out.',
  water_summer = 'Keep lightly moist; water when the top few cm feel dry.',
  water_autumn = 'Allow more drying between waterings.',
  water_winter = 'Water sparingly; it tolerates a drier winter.',
  water_topcm = 3,
  fertilizer_type = 'Balanced liquid houseplant fertiliser',
  fertilizer_freq = 'Monthly in spring and summer',
  fertilizer_months = ARRAY['April','May','June','July','August','September'],
  fertilizer_winter_pause = true,
  repot_interval = 'Every 1–2 years',
  repot_pot_step_cm = 3, repot_period = 'Spring'
where slug = 'epipremnum-aureum';

update public.plant_species set
  light_lux_min = 400, light_lux_ideal = 1500, light_lux_max = 15000,
  temp_ideal_min = 18, temp_ideal_max = 27, temp_accepted_min = 15, temp_accepted_max = 30,
  temp_danger_low = 10, temp_danger_high = 35,
  humidity_ideal_min = 30, humidity_ideal_max = 50, humidity_accepted_min = 20, humidity_accepted_max = 60,
  ph_min = 6.0, ph_ideal = 6.5, ph_max = 7.0,
  substrate_mix = '{"potting_soil":60,"perlite":20,"sand":20}'::jsonb,
  water_spring = 'Water only when the soil is dry throughout.',
  water_summer = 'Water when fully dry; the rhizomes store water.',
  water_autumn = 'Reduce watering.',
  water_winter = 'Water rarely; it tolerates weeks without water.',
  fertilizer_type = 'Balanced liquid feed, diluted',
  fertilizer_freq = 'Once or twice in spring and summer',
  fertilizer_months = ARRAY['May','July'],
  fertilizer_winter_pause = true,
  repot_interval = 'Every 2–3 years',
  repot_pot_step_cm = 3, repot_period = 'Spring'
where slug = 'zamioculcas-zamiifolia';

update public.plant_species set
  light_lux_min = 500, light_lux_ideal = 1500, light_lux_max = 10000,
  temp_ideal_min = 18, temp_ideal_max = 27, temp_accepted_min = 15, temp_accepted_max = 30,
  temp_danger_low = 12, temp_danger_high = 35,
  humidity_ideal_min = 50, humidity_ideal_max = 80, humidity_accepted_min = 40, humidity_accepted_max = 90,
  ph_min = 5.5, ph_ideal = 6.0, ph_max = 6.5,
  water_spring = 'Keep evenly moist; water when the very top starts to dry.',
  water_summer = 'Water regularly; it wilts fast when dry but recovers quickly.',
  water_autumn = 'Reduce slightly as growth slows.',
  water_winter = 'Keep just moist; avoid cold and soggy soil.',
  water_topcm = 1,
  fertilizer_type = 'Balanced liquid houseplant fertiliser',
  fertilizer_freq = 'Every 4–6 weeks in spring and summer',
  fertilizer_months = ARRAY['April','May','June','July','August','September'],
  fertilizer_winter_pause = true,
  repot_interval = 'Every 1–2 years',
  repot_pot_step_cm = 3, repot_period = 'Spring'
where slug = 'spathiphyllum-wallisii';

update public.plant_species set
  light_lux_min = 3000, light_lux_ideal = 15000, light_lux_max = 60000,
  temp_ideal_min = 18, temp_ideal_max = 27, temp_accepted_min = 10, temp_accepted_max = 30,
  temp_danger_low = 5, temp_danger_high = 40,
  humidity_ideal_min = 30, humidity_ideal_max = 50, humidity_accepted_min = 10, humidity_accepted_max = 60,
  ph_min = 6.0, ph_ideal = 6.5, ph_max = 7.5,
  substrate_mix = '{"potting_soil":50,"sand":30,"perlite":20}'::jsonb,
  water_spring = 'Water deeply, then let the soil dry out completely.',
  water_summer = 'Water when fully dry; the leaves store water.',
  water_autumn = 'Water less frequently.',
  water_winter = 'Water minimally, roughly monthly; keep frost-free.',
  fertilizer_type = 'Low-nitrogen cactus/succulent feed',
  fertilizer_freq = 'Once or twice in spring and summer',
  fertilizer_months = ARRAY['May','July'],
  fertilizer_winter_pause = true,
  repot_interval = 'Every 2–3 years, or when crowded with pups',
  repot_pot_step_cm = 3, repot_period = 'Spring'
where slug = 'aloe-vera';

update public.plant_species set
  light_lux_min = 800, light_lux_ideal = 2000, light_lux_max = 15000,
  temp_ideal_min = 18, temp_ideal_max = 27, temp_accepted_min = 13, temp_accepted_max = 30,
  temp_danger_low = 7, temp_danger_high = 35,
  humidity_ideal_min = 40, humidity_ideal_max = 60, humidity_accepted_min = 30, humidity_accepted_max = 70,
  water_spring = 'Keep lightly moist; water when the top 2 cm dries.',
  water_summer = 'Water regularly; use filtered water to avoid tip burn.',
  water_autumn = 'Reduce watering.',
  water_winter = 'Water less; let the top few cm dry first.',
  water_topcm = 2,
  fertilizer_type = 'Balanced liquid houseplant fertiliser',
  fertilizer_freq = 'Monthly in spring and summer',
  fertilizer_months = ARRAY['April','May','June','July','August','September'],
  fertilizer_winter_pause = true,
  repot_interval = 'Every 1–2 years; the fleshy roots fill the pot fast',
  repot_pot_step_cm = 3, repot_period = 'Spring'
where slug = 'chlorophytum-comosum';

update public.plant_species set
  light_lux_min = 800, light_lux_ideal = 2000, light_lux_max = 15000,
  temp_ideal_min = 18, temp_ideal_max = 27, temp_accepted_min = 15, temp_accepted_max = 30,
  temp_danger_low = 12, temp_danger_high = 35,
  humidity_ideal_min = 40, humidity_ideal_max = 60, humidity_accepted_min = 30, humidity_accepted_max = 70,
  water_spring = 'Water when the top few cm are dry.',
  water_summer = 'Water when the top 3 cm dries; use filtered water if tips brown.',
  water_autumn = 'Reduce watering.',
  water_winter = 'Water sparingly; keep warm.',
  water_topcm = 3,
  fertilizer_type = 'Balanced liquid houseplant fertiliser',
  fertilizer_freq = 'Monthly in spring and summer',
  fertilizer_months = ARRAY['April','May','June','July','August','September'],
  fertilizer_winter_pause = true,
  repot_interval = 'Every 2–3 years',
  repot_pot_step_cm = 3, repot_period = 'Spring'
where slug = 'dracaena-marginata';

update public.plant_species set
  light_lux_min = 800, light_lux_ideal = 2000, light_lux_max = 15000,
  temp_ideal_min = 18, temp_ideal_max = 27, temp_accepted_min = 15, temp_accepted_max = 30,
  temp_danger_low = 12, temp_danger_high = 35,
  humidity_ideal_min = 50, humidity_ideal_max = 70, humidity_accepted_min = 40, humidity_accepted_max = 90,
  ph_min = 5.5, ph_ideal = 6.0, ph_max = 7.0,
  substrate_mix = '{"coco":40,"perlite":30,"bark":30}'::jsonb,
  water_spring = 'Water when the top 2 cm dries out.',
  water_summer = 'Keep lightly moist during active growth.',
  water_autumn = 'Allow more drying between waterings.',
  water_winter = 'Water sparingly.',
  water_topcm = 2,
  fertilizer_type = 'Balanced liquid houseplant fertiliser',
  fertilizer_freq = 'Monthly in spring and summer',
  fertilizer_months = ARRAY['April','May','June','July','August','September'],
  fertilizer_winter_pause = true,
  repot_interval = 'Every 1–2 years',
  repot_pot_step_cm = 3, repot_period = 'Spring'
where slug = 'philodendron-hederaceum';

update public.plant_species set
  light_lux_min = 1000, light_lux_ideal = 2500, light_lux_max = 20000,
  temp_ideal_min = 18, temp_ideal_max = 27, temp_accepted_min = 15, temp_accepted_max = 30,
  temp_danger_low = 12, temp_danger_high = 35,
  humidity_ideal_min = 40, humidity_ideal_max = 60, humidity_accepted_min = 30, humidity_accepted_max = 70,
  ph_min = 5.5, ph_ideal = 6.0, ph_max = 7.0,
  water_spring = 'Water when the top 3 cm feels dry; wipe the leaves to keep them glossy.',
  water_summer = 'Water when the top 3 cm dries.',
  water_autumn = 'Reduce watering as light drops.',
  water_winter = 'Water sparingly; avoid cold, wet soil.',
  water_topcm = 3,
  fertilizer_type = 'Balanced liquid houseplant fertiliser',
  fertilizer_freq = 'Monthly in spring and summer',
  fertilizer_months = ARRAY['April','May','June','July','August','September'],
  fertilizer_winter_pause = true,
  repot_interval = 'Every 1–2 years while young',
  repot_pot_step_cm = 3, repot_period = 'Spring'
where slug = 'ficus-elastica';

update public.plant_species set
  light_lux_min = 500, light_lux_ideal = 1500, light_lux_max = 8000,
  temp_ideal_min = 18, temp_ideal_max = 27, temp_accepted_min = 16, temp_accepted_max = 30,
  temp_danger_low = 13, temp_danger_high = 32,
  humidity_ideal_min = 60, humidity_ideal_max = 90, humidity_accepted_min = 50, humidity_accepted_max = 99,
  ph_min = 5.5, ph_ideal = 6.0, ph_max = 6.5,
  water_spring = 'Keep evenly moist with filtered or rainwater; do not let it dry out fully.',
  water_summer = 'Water regularly; high humidity matters as much as watering.',
  water_autumn = 'Keep lightly moist.',
  water_winter = 'Reduce slightly but keep the soil from drying; avoid cold.',
  water_topcm = 1,
  fertilizer_type = 'Balanced liquid feed, diluted',
  fertilizer_freq = 'Every 4–6 weeks in spring and summer',
  fertilizer_months = ARRAY['April','May','June','July','August','September'],
  fertilizer_winter_pause = true,
  repot_interval = 'Every 1–2 years',
  repot_pot_step_cm = 3, repot_period = 'Spring'
where slug = 'calathea-orbifolia';

update public.plant_species set
  light_lux_min = 500, light_lux_ideal = 1500, light_lux_max = 8000,
  temp_ideal_min = 18, temp_ideal_max = 27, temp_accepted_min = 13, temp_accepted_max = 30,
  temp_danger_low = 10, temp_danger_high = 35,
  humidity_ideal_min = 50, humidity_ideal_max = 70, humidity_accepted_min = 40, humidity_accepted_max = 80,
  water_spring = 'Keep lightly moist; water when the top 2 cm dries.',
  water_summer = 'Water regularly; avoid both drought and waterlogging.',
  water_autumn = 'Reduce watering.',
  water_winter = 'Water less; keep out of cold draughts.',
  water_topcm = 2,
  fertilizer_type = 'Balanced liquid feed, diluted',
  fertilizer_freq = 'Every 6–8 weeks in spring and summer',
  fertilizer_months = ARRAY['May','June','July','August'],
  fertilizer_winter_pause = true,
  repot_interval = 'Every 2–3 years; palms dislike root disturbance',
  repot_pot_step_cm = 3, repot_period = 'Spring'
where slug = 'chamaedorea-elegans';

update public.plant_species set
  light_lux_min = 1000, light_lux_ideal = 3000, light_lux_max = 20000,
  temp_ideal_min = 10, temp_ideal_max = 18, temp_accepted_min = 2, temp_accepted_max = 24,
  temp_danger_low = -5, temp_danger_high = 30,
  humidity_ideal_min = 40, humidity_ideal_max = 60, humidity_accepted_min = 30, humidity_accepted_max = 70,
  water_spring = 'Keep lightly moist; water when the top 2 cm dries.',
  water_summer = 'Water regularly in heat; do not let it dry out completely.',
  water_autumn = 'Reduce watering.',
  water_winter = 'Water sparingly; it tolerates cool, even cold, conditions.',
  water_topcm = 2,
  fertilizer_type = 'Balanced liquid houseplant fertiliser',
  fertilizer_freq = 'Monthly in spring and summer',
  fertilizer_months = ARRAY['April','May','June','July','August'],
  fertilizer_winter_pause = true,
  repot_interval = 'Every 1–2 years',
  repot_pot_step_cm = 3, repot_period = 'Spring'
where slug = 'hedera-helix';

update public.plant_species set
  light_lux_min = 3000, light_lux_ideal = 15000, light_lux_max = 50000,
  temp_ideal_min = 18, temp_ideal_max = 27, temp_accepted_min = 10, temp_accepted_max = 30,
  temp_danger_low = 5, temp_danger_high = 38,
  humidity_ideal_min = 30, humidity_ideal_max = 50, humidity_accepted_min = 10, humidity_accepted_max = 60,
  ph_min = 6.0, ph_ideal = 6.5, ph_max = 7.0,
  substrate_mix = '{"potting_soil":50,"sand":30,"perlite":20}'::jsonb,
  water_spring = 'Water when the soil is dry, then soak; give bright light.',
  water_summer = 'Water when fully dry; the leaves store water.',
  water_autumn = 'Reduce watering to prepare for a cool, dry winter rest.',
  water_winter = 'Keep nearly dry and cool to encourage flowering.',
  fertilizer_type = 'Low-nitrogen cactus/succulent feed',
  fertilizer_freq = 'Once or twice in spring and summer',
  fertilizer_months = ARRAY['May','July'],
  fertilizer_winter_pause = true,
  repot_interval = 'Every 2–3 years, or when top-heavy',
  repot_pot_step_cm = 3, repot_period = 'Spring'
where slug = 'crassula-ovata';
