-- 150: Persist the task work-session timer.
--
-- WorkSessionStore already accumulates worked time locally and
-- TaskService.updateWorkedSeconds writes it — silently no-oping until this
-- column exists. Total seconds ever worked on the task, monotonic.

alter table public.maintenance_tasks
  add column if not exists worked_seconds integer not null default 0;
