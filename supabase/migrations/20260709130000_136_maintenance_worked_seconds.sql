-- 136: total time worked per maintenance task (work-session timer).
--
-- The iOS work-session timer (Start / Pause / Finish) banks elapsed time onto
-- a running per-task total. The app keeps that total locally in the App Group
-- so it always works offline; this column is the server mirror so the number
-- follows the household across devices. TaskService.persistWorkedSeconds writes
-- it best-effort and silently no-ops until this migration ships — so applying
-- this is purely additive and safe to run at any time.

alter table public.maintenance_tasks
    add column if not exists worked_seconds integer not null default 0;

comment on column public.maintenance_tasks.worked_seconds is
    'Total seconds logged against this task by the work-session timer.';
