-- 153: Estate OS E1 — a zone can declare WHAT KIND of space it is
-- (pond, garden, forest, greenhouse, garage, basement, house, custom).
-- Nullable text, no constraint: the app owns the vocabulary and treats
-- unknown/null as "custom", so old rows and old clients are untouched.
ALTER TABLE public.property_zones
    ADD COLUMN IF NOT EXISTS space_kind text;
