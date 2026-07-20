-- 171: Inventory metadata backfill (applied live 2026-07-19).
--
-- The four seed items created with each early property (2026-06-10) carried
-- metadata = '{}'. The iOS InventoryMetadata decoder (synthesized Codable)
-- requires location/loanHistory/trackerType/trackerIdentifier, so ONE such
-- row failed its decode and — array decoding being all-or-nothing — emptied
-- the ENTIRE inventory list. The failure was masked for weeks by the local
-- cache + in-place inserts and surfaced the moment a fresh install (or a
-- cache purge on app update) forced a clean network load.
--
-- Merge the required keys under any existing metadata (existing values win).
-- Build 1161 additionally makes the client decoder tolerant, so this class
-- of row can never poison the list again.

update public.inventory_items
set metadata = jsonb_build_object(
      'location', 'garage',
      'loanHistory', jsonb '[]',
      'trackerType', '',
      'trackerIdentifier', '') || coalesce(metadata, '{}'::jsonb)
where metadata is null
   or not (metadata ?& array['location','loanHistory','trackerType','trackerIdentifier']);
