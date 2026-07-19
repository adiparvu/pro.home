-- One round-trip world load: every startup table in a single RPC, each
-- slice serialized to TEXT so the client hands the exact bytes to its
-- decoder (no numeric re-serialization drift on Decimal money fields).
-- SECURITY INVOKER: RLS applies to the caller exactly as in the
-- per-table PostgREST path. The per-table WHERE/ORDER/LIMIT mirror the
-- iOS services' PropertyRepo.fetch calls verbatim (see
-- PropertyRepo.bootstrapSpecs — the two must stay in lockstep).

create or replace function public.app_bootstrap(p_property_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
select jsonb_build_object(
  'maintenance_tasks', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)::text from (
      select * from maintenance_tasks
      where property_id = p_property_id or property_id is null
      order by created_at desc limit 500) t),
  'plants', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)::text from (
      select * from plants
      where property_id = p_property_id
      order by created_at asc limit 500) t),
  'supply_lists', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)::text from (
      select * from supply_lists
      where property_id = p_property_id
      order by created_at asc limit 500) t),
  'supply_items', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)::text from (
      select * from supply_items
      where property_id = p_property_id
      order by created_at asc limit 1000) t),
  'pantry_items', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)::text from (
      select * from pantry_items
      where property_id = p_property_id
      order by created_at asc limit 500) t),
  'packages', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)::text from (
      select * from packages
      where property_id = p_property_id
      order by created_at desc limit 500) t),
  'documents', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)::text from (
      select * from documents
      where property_id = p_property_id or property_id is null
      order by created_at desc limit 500) t),
  'financial_records', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)::text from (
      select * from financial_records
      where property_id = p_property_id or property_id is null
      order by date desc limit 1000) t),
  'appliances', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)::text from (
      select * from appliances
      where property_id = p_property_id
      order by created_at asc limit 500) t),
  'calendar_events', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)::text from (
      select * from calendar_events
      where property_id = p_property_id
      order by starts_at asc limit 1000) t),
  'inventory_items', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)::text from (
      select * from inventory_items
      where property_id = p_property_id
      order by created_at desc limit 1000) t),
  'family_members', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)::text from (
      select * from family_members
      where property_id = p_property_id or property_id is null
      order by created_at asc limit 500) t),
  'photo_journal_entries', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)::text from (
      select * from photo_journal_entries
      where property_id = p_property_id
      order by taken_at desc limit 600) t)
);
$$;
