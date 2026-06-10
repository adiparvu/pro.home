-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 018: Push dispatch tracking
-- ═══════════════════════════════════════════════════════════════════════════
-- pushed_at marks notifications already delivered via Web Push so the
-- dispatch endpoint can be called repeatedly without duplicate pushes.

alter table public.notifications add column if not exists pushed_at timestamptz;
create index if not exists idx_notifications_unpushed on public.notifications(created_at) where pushed_at is null;
