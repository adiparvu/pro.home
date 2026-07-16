-- 157: Calendar C2 — the household's OWN calendar events.
--
-- Until now the house calendar was a pure aggregation (task due dates, doc
-- expiries, birthdays, bills, plant care, leases). This table adds first-class,
-- user-created events so the calendar can hold anything — a viewing, a repair
-- window, a family plan — alongside those derived deadlines.
--
-- `starts_at` / `ends_at` are stored as the SAME wall-clock string the app
-- already speaks for task due dates: "yyyy-MM-dd" for an all-day event or
-- "yyyy-MM-dd HH:mm" for a timed one. HouseAgenda then parses them with the
-- one AppDate authority, so there is no timezone conversion surprise and no
-- new date pipeline. `all_day` disambiguates rendering when a time is absent.
CREATE TABLE IF NOT EXISTS public.calendar_events (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
    title       text NOT NULL,
    notes       text,
    starts_at   text NOT NULL,
    ends_at     text,
    all_day     boolean NOT NULL DEFAULT true,
    -- Optional brand-token name (e.g. "brandPurple") so an event can carry its
    -- own accent; the app falls back to the default event colour when null.
    color       text,
    location    text,
    created_by  uuid NOT NULL DEFAULT auth.uid(),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS calendar_events_property_idx
    ON public.calendar_events (property_id, starts_at);

ALTER TABLE public.calendar_events ENABLE ROW LEVEL SECURITY;

-- Household members read and manage the home's events — the same membership
-- test every sibling household table uses.
DROP POLICY IF EXISTS calendar_events_select ON public.calendar_events;
DROP POLICY IF EXISTS calendar_events_insert ON public.calendar_events;
DROP POLICY IF EXISTS calendar_events_update ON public.calendar_events;
DROP POLICY IF EXISTS calendar_events_delete ON public.calendar_events;

CREATE POLICY calendar_events_select ON public.calendar_events
    FOR SELECT USING (public.is_property_member(property_id));
CREATE POLICY calendar_events_insert ON public.calendar_events
    FOR INSERT WITH CHECK (public.is_property_member(property_id));
CREATE POLICY calendar_events_update ON public.calendar_events
    FOR UPDATE USING (public.is_property_member(property_id));
CREATE POLICY calendar_events_delete ON public.calendar_events
    FOR DELETE USING (public.is_property_member(property_id));
