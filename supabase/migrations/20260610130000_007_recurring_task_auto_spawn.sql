-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 007: Auto-spawn next recurring maintenance task
-- ═══════════════════════════════════════════════════════════════════════════
-- When a recurring task is marked completed, insert the next occurrence
-- using the task's recurrence_rule interval.

create or replace function public.create_next_recurring_task()
returns trigger as $$
declare
  v_next_due date;
  v_interval interval;
begin
  -- Only act on the completed → completed transition for recurring tasks
  if new.status <> 'completed' then return new; end if;
  if old.status = 'completed' then return new; end if;
  if not new.is_recurring then return new; end if;
  if new.recurrence_rule is null then return new; end if;

  -- Resolve interval from simple rule strings
  v_interval := case new.recurrence_rule
    when 'daily'          then interval '1 day'
    when 'weekly'         then interval '7 days'
    when 'monthly'        then interval '1 month'
    when 'every_3_months' then interval '3 months'
    when 'every_6_months' then interval '6 months'
    when 'yearly'         then interval '1 year'
    else null
  end;

  -- Unknown rule — skip silently
  if v_interval is null then return new; end if;

  -- Base date: original due_date if set, otherwise today
  v_next_due := (coalesce(new.due_date, current_date)::date + v_interval)::date;

  -- Insert next occurrence (pending, same template as parent)
  insert into public.maintenance_tasks (
    property_id, room_id, inventory_item_id,
    title, description, category, priority,
    status, due_date,
    estimated_cost, estimated_hours,
    is_recurring, recurrence_rule, parent_task_id,
    assigned_to_member_id, checklist, tags, notes
  ) values (
    new.property_id, new.room_id, new.inventory_item_id,
    new.title, new.description, new.category, new.priority,
    'pending', v_next_due,
    new.estimated_cost, new.estimated_hours,
    true, new.recurrence_rule, new.id,
    new.assigned_to_member_id, new.checklist, new.tags, new.notes
  );

  -- Record the next due date on the completed task for reference
  update public.maintenance_tasks
  set next_due_date = v_next_due
  where id = new.id;

  return new;
end;
$$ language plpgsql security definer;

create trigger trg_create_next_recurring_task
  after update of status on public.maintenance_tasks
  for each row execute function public.create_next_recurring_task();
