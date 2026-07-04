-- 090 — role-based RLS, phase 3 (part 2): tasks (maintenance_tasks)
--
-- assignee_ids holds family_members.id strings. A scoped member (tenant,
-- service_provider, child, teen) sees a task only if their linked contact
-- (family_members.user_id = auth.uid()) is among its assignees. Household
-- adults keep full visibility; guests, with no assignments, see nothing.
--
-- The assignee check must be SECURITY DEFINER: family_members has its own
-- (owner-scoped) RLS, so an inline subquery in the policy would run as the
-- querying member and find nothing. The helper bypasses that to answer purely
-- "is auth.uid()'s contact an assignee of this task?".

create or replace function public.is_task_assignee(p_property_id uuid, p_assignee_ids text[])
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce(exists (
    select 1 from public.family_members fm
    where fm.user_id = auth.uid()
      and fm.property_id = p_property_id
      and fm.id::text = any(p_assignee_ids)
  ), false);
$$;

grant execute on function public.is_task_assignee(uuid, text[]) to authenticated;

drop policy if exists tasks_select_member on public.maintenance_tasks;
create policy tasks_select_member on public.maintenance_tasks
  for select using (
    public.has_household_access(property_id)
    or public.is_task_assignee(property_id, assignee_ids)
  );

-- Assignees may update their own task (e.g. mark it done) even when they're not
-- a household adult. with_check keeps them from reassigning it away from
-- themselves. Household write access is unchanged (tasks_update_write).
drop policy if exists tasks_update_assignee on public.maintenance_tasks;
create policy tasks_update_assignee on public.maintenance_tasks
  for update
  using (public.is_task_assignee(property_id, assignee_ids))
  with check (public.is_task_assignee(property_id, assignee_ids));
