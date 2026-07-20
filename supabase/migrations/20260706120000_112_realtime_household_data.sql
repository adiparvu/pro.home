-- 112: Live family sync for household data.
--
-- Chat, notifications and presence already stream over supabase_realtime,
-- but the data that defines the home — tasks and money — refreshed only on
-- pull-to-refresh, so two family members routinely looked at different
-- states of the same house. Add the two highest-churn tables to the
-- publication; the app subscribes per-property and coalesces reloads.
--
-- RLS still applies to realtime (postgres_changes respects row policies),
-- so members only ever receive events for properties they belong to.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'maintenance_tasks'
  ) then
    execute 'alter publication supabase_realtime add table public.maintenance_tasks';
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'financial_records'
  ) then
    execute 'alter publication supabase_realtime add table public.financial_records';
  end if;
end $$;

-- Realtime delivers old/new row images for updates/deletes based on replica
-- identity; FULL is not required for the app's reload-on-any-event strategy,
-- but explicit DEFAULT documents the choice.
alter table public.maintenance_tasks replica identity default;
alter table public.financial_records replica identity default;
