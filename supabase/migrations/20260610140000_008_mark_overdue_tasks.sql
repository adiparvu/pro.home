-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 008: On-demand overdue task marking
-- ═══════════════════════════════════════════════════════════════════════════
-- Transitions pending/in_progress tasks whose due_date has passed to
-- 'overdue'. Called on each maintenance page load for the active property.
-- The existing trg_notify_on_task_overdue trigger then fires automatically
-- for each row that transitions, surfacing a notification.

create or replace function public.mark_overdue_tasks(p_property_id uuid)
returns integer as $$
declare
  v_count integer;
begin
  update public.maintenance_tasks
  set status = 'overdue'
  where property_id = p_property_id
    and status in ('pending', 'in_progress')
    and due_date is not null
    and due_date < current_date;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$ language plpgsql security definer;

grant execute on function public.mark_overdue_tasks(uuid) to authenticated;
