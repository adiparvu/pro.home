-- 082: restore direct_messages.property_id — the column the client depends on.
--
-- The live direct_messages table had drifted and lost property_id (migration 049
-- originally defined it). The iOS DM code references property_id everywhere — the
-- send payloads insert it, load() filters `.eq("property_id", …)`, and the
-- realtime subscription filters `property_id=eq.…`. With the column missing,
-- every insert/select/subscribe errors and is swallowed, so DMs neither send,
-- load, nor stream on the live backend.
--
-- The table is empty, so restoring the column (nullable, FK to properties) is a
-- clean, zero-data-loss fix that re-aligns the schema with the client and makes
-- direct messaging work again. RLS (dm_select/insert/update/delete, name-based)
-- is unaffected.

ALTER TABLE public.direct_messages
    ADD COLUMN IF NOT EXISTS property_id uuid REFERENCES public.properties(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_dm_property_created
    ON public.direct_messages(property_id, created_at DESC);
