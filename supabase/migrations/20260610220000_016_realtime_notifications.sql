-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 016: Realtime on notifications
-- ═══════════════════════════════════════════════════════════════════════════
-- Lets clients subscribe to their own notification inserts for live toasts
-- and badge updates without polling.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
