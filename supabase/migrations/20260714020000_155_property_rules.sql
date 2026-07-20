-- 155: Smart Control R5 — the PRVIO rules engine's storage.
-- A rule watches ONE condition (a sensor threshold or a weather state)
-- and fires actions (local notification / create task / run HomeKit
-- scene). Conditions/actions are jsonb: the APP owns the vocabulary,
-- evaluation happens client-side while the app runs (documented in-app),
-- so unknown shapes must never break old clients.
CREATE TABLE IF NOT EXISTS public.property_rules (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id   uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
    name          text NOT NULL,
    enabled       boolean NOT NULL DEFAULT true,
    condition     jsonb NOT NULL,
    actions       jsonb NOT NULL DEFAULT '[]'::jsonb,
    cooldown_minutes integer NOT NULL DEFAULT 60,
    last_fired_at timestamptz,
    created_by    uuid NOT NULL DEFAULT auth.uid(),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS property_rules_property_idx
    ON public.property_rules (property_id, enabled);

ALTER TABLE public.property_rules ENABLE ROW LEVEL SECURITY;

-- Household members read and manage the home's rules (same membership
-- test the sibling household tables use).
CREATE POLICY property_rules_select ON public.property_rules
    FOR SELECT USING (public.is_property_member(property_id));
CREATE POLICY property_rules_insert ON public.property_rules
    FOR INSERT WITH CHECK (public.is_property_member(property_id));
CREATE POLICY property_rules_update ON public.property_rules
    FOR UPDATE USING (public.is_property_member(property_id));
CREATE POLICY property_rules_delete ON public.property_rules
    FOR DELETE USING (public.is_property_member(property_id));
