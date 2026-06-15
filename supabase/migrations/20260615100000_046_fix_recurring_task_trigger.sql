-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 046: Fix recurring task trigger
-- ═══════════════════════════════════════════════════════════════════════════
-- The original create_next_recurring_task() (migration 007) did:
--
--   UPDATE maintenance_tasks SET next_due_date = v_next_due WHERE id = new.id
--
-- inside an AFTER ROW trigger. PostgreSQL prohibits updating the same row
-- that triggered an AFTER trigger within the same command, which caused:
--
--   "tuple to be updated was already modified by an operation triggered
--    by the current command"
--
-- Fix: remove that UPDATE entirely. The spawned child task carries its own
-- due_date; next_due_date on the completed row is redundant.

create or replace function public.create_next_recurring_task()
returns trigger as $$
declare
  v_next_due date;
  v_interval interval;
begin
  if new.status <> 'completed'   then return new; end if;
  if old.status = 'completed'    then return new; end if;
  if not new.is_recurring        then return new; end if;
  if new.recurrence_rule is null then return new; end if;

  v_interval := case new.recurrence_rule
    when 'daily'          then interval '1 day'
    when 'weekly'         then interval '7 days'
    when 'monthly'        then interval '1 month'
    when 'every_3_months' then interval '3 months'
    when 'every_6_months' then interval '6 months'
    when 'yearly'         then interval '1 year'
    else null
  end;
  if v_interval is null then return new; end if;

  v_next_due := (coalesce(new.due_date, current_date)::date + v_interval)::date;

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

  return new;
end;
$$ language plpgsql security definer;
