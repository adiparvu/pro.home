-- Pond OS — Supabase Migration
-- Branch: claude/ha-plugin-catalog
-- Follows the exact same conventions as existing PRVIO migrations.

-- ─── Ponds ───────────────────────────────────────────────────────────────────

CREATE TABLE ponds (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id     UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    type            TEXT NOT NULL DEFAULT 'ornamental',
    volume_liters   FLOAT,
    surface_area_sqm FLOAT,
    max_depth_cm    FLOAT,
    photo_url       TEXT,
    ha_instance_id  UUID REFERENCES ha_instances(id) ON DELETE SET NULL,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX ponds_property_id_idx ON ponds(property_id);

-- ─── Pond Zones ──────────────────────────────────────────────────────────────

CREATE TABLE pond_zones (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pond_id         UUID NOT NULL REFERENCES ponds(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    zone_type       TEXT NOT NULL,
    position_x      FLOAT NOT NULL DEFAULT 0.5,
    position_y      FLOAT NOT NULL DEFAULT 0.5,
    radius_percent  FLOAT NOT NULL DEFAULT 0.2,
    color_hex       TEXT NOT NULL DEFAULT '#5AC8FA',
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX pond_zones_pond_id_idx ON pond_zones(pond_id);

-- ─── Pond Equipment ──────────────────────────────────────────────────────────

CREATE TABLE pond_equipment (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pond_id             UUID NOT NULL REFERENCES ponds(id) ON DELETE CASCADE,
    name                TEXT NOT NULL,
    type                TEXT NOT NULL,
    brand               TEXT,
    model               TEXT,
    position_x          FLOAT NOT NULL DEFAULT 0.5,
    position_y          FLOAT NOT NULL DEFAULT 0.5,
    is_running          BOOLEAN NOT NULL DEFAULT false,
    ha_entity_id        TEXT,
    power_watts         FLOAT,
    last_maintenance_at TIMESTAMPTZ,
    warranty_until      TIMESTAMPTZ,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX pond_equipment_pond_id_idx ON pond_equipment(pond_id);
CREATE INDEX pond_equipment_ha_entity_idx ON pond_equipment(ha_entity_id) WHERE ha_entity_id IS NOT NULL;

-- ─── Water Quality Readings ───────────────────────────────────────────────────
-- Note: reuses the same time-series pattern as sensor_readings (from PRVIO V1.F5)
-- Kept separate to avoid cross-contamination of pond data with property sensor data.

CREATE TABLE water_quality_readings (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pond_id     UUID NOT NULL REFERENCES ponds(id) ON DELETE CASCADE,
    parameter   TEXT NOT NULL,  -- WaterParameter.rawValue
    value       FLOAT NOT NULL,
    source      TEXT NOT NULL DEFAULT 'manual',  -- 'manual' | 'ha:entity_id' | 'esphome:entity_id'
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (recorded_at);

-- Partitions (monthly, create new ones as needed)
CREATE TABLE water_quality_readings_2026_06 PARTITION OF water_quality_readings
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE water_quality_readings_2026_07 PARTITION OF water_quality_readings
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE water_quality_readings_2026_08 PARTITION OF water_quality_readings
    FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');

CREATE INDEX wq_readings_pond_param_idx ON water_quality_readings(pond_id, parameter, recorded_at DESC);

-- ─── Pond Alerts ─────────────────────────────────────────────────────────────

CREATE TABLE pond_alerts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pond_id         UUID NOT NULL REFERENCES ponds(id) ON DELETE CASCADE,
    parameter       TEXT,
    severity        TEXT NOT NULL DEFAULT 'info',  -- info | warning | critical
    title           TEXT NOT NULL,
    message         TEXT NOT NULL,
    is_acknowledged BOOLEAN NOT NULL DEFAULT false,
    triggered_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at     TIMESTAMPTZ
);

CREATE INDEX pond_alerts_pond_active_idx ON pond_alerts(pond_id, resolved_at) WHERE resolved_at IS NULL;

-- ─── Fish Populations ─────────────────────────────────────────────────────────

CREATE TABLE fish_populations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pond_id             UUID NOT NULL REFERENCES ponds(id) ON DELETE CASCADE,
    species_id          TEXT NOT NULL,
    estimated_count     INT NOT NULL DEFAULT 0,
    average_length_cm   FLOAT,
    average_weight_kg   FLOAT,
    color_variety       TEXT,
    source_notes        TEXT,
    notes               TEXT,
    added_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX fish_populations_pond_id_idx ON fish_populations(pond_id);

-- ─── Fish Journal ─────────────────────────────────────────────────────────────

CREATE TABLE fish_journal (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pond_id     UUID NOT NULL REFERENCES ponds(id) ON DELETE CASCADE,
    event       TEXT NOT NULL,  -- FishEvent.rawValue
    count       INT,
    species_id  TEXT,
    notes       TEXT,
    photo_url   TEXT,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX fish_journal_pond_id_idx ON fish_journal(pond_id, recorded_at DESC);

-- ─── Feeding Schedules ────────────────────────────────────────────────────────

CREATE TABLE feeding_schedules (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pond_id             UUID NOT NULL REFERENCES ponds(id) ON DELETE CASCADE,
    name                TEXT NOT NULL,
    hour                INT NOT NULL CHECK (hour >= 0 AND hour <= 23),
    minute              INT NOT NULL CHECK (minute >= 0 AND minute <= 59),
    food_type           TEXT NOT NULL DEFAULT 'pellet',
    amount_grams        FLOAT NOT NULL,
    is_active           BOOLEAN NOT NULL DEFAULT true,
    days_of_week        INT[] NOT NULL DEFAULT '{}',  -- empty = every day
    ha_feeder_entity_id TEXT,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX feeding_schedules_pond_id_idx ON feeding_schedules(pond_id);

-- ─── Feeding Logs ─────────────────────────────────────────────────────────────

CREATE TABLE feeding_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pond_id         UUID NOT NULL REFERENCES ponds(id) ON DELETE CASCADE,
    schedule_id     UUID REFERENCES feeding_schedules(id) ON DELETE SET NULL,
    food_type       TEXT NOT NULL,
    amount_grams    FLOAT NOT NULL,
    source          TEXT NOT NULL DEFAULT 'manual',  -- manual | automatic | aria
    notes           TEXT,
    fed_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX feeding_logs_pond_id_idx ON feeding_logs(pond_id, fed_at DESC);

-- ─── HA Entity Mappings Extension ─────────────────────────────────────────────
-- Extends ha_entity_mappings (from PRVIO V1.D8) with pond_id column.
-- Only add if ha_entity_mappings exists (V1 deployed).

ALTER TABLE ha_entity_mappings ADD COLUMN IF NOT EXISTS pond_id UUID REFERENCES ponds(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS ha_entity_mappings_pond_idx ON ha_entity_mappings(pond_id) WHERE pond_id IS NOT NULL;

-- ─── Row Level Security ───────────────────────────────────────────────────────

ALTER TABLE ponds ENABLE ROW LEVEL SECURITY;
ALTER TABLE pond_zones ENABLE ROW LEVEL SECURITY;
ALTER TABLE pond_equipment ENABLE ROW LEVEL SECURITY;
ALTER TABLE water_quality_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE pond_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE fish_populations ENABLE ROW LEVEL SECURITY;
ALTER TABLE fish_journal ENABLE ROW LEVEL SECURITY;
ALTER TABLE feeding_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE feeding_logs ENABLE ROW LEVEL SECURITY;

-- Users can access ponds on their properties only.
-- Reuses the same RLS pattern as property_zones.

CREATE POLICY "Property members can view ponds"
    ON ponds FOR SELECT
    USING (
        property_id IN (
            SELECT property_id FROM property_members
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Property owners/managers can manage ponds"
    ON ponds FOR ALL
    USING (
        property_id IN (
            SELECT property_id FROM property_members
            WHERE user_id = auth.uid()
            AND role IN ('owner', 'manager')
        )
    );

-- Cascade policies for child tables (pond_id → ponds → property_members)
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'pond_zones', 'pond_equipment', 'water_quality_readings',
        'pond_alerts', 'fish_populations', 'fish_journal',
        'feeding_schedules', 'feeding_logs'
    ]
    LOOP
        EXECUTE format('
            CREATE POLICY "Members access %s via pond"
            ON %s FOR ALL
            USING (
                pond_id IN (
                    SELECT id FROM ponds WHERE property_id IN (
                        SELECT property_id FROM property_members WHERE user_id = auth.uid()
                    )
                )
            );
        ', t, t);
    END LOOP;
END$$;

-- ─── Updated At Trigger (same as existing pattern) ────────────────────────────

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ponds_updated_at
    BEFORE UPDATE ON ponds
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
