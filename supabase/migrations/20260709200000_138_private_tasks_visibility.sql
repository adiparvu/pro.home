-- 138: Tasks are private per person. Until now any household adult saw EVERY
-- task (tasks_select_member OR'd in has_household_access). Per the owner's
-- request tasks are now per-person: you see only what you CREATED plus tasks
-- you're tagged (assigned) into — symmetric for everyone, including the owner.

alter table public.maintenance_tasks alter column created_by set default auth.uid();

update public.maintenance_tasks t
set created_by = (
  select pm.user_id
  from public.property_members pm
  where pm.property_id = t.property_id
    and pm.role = 'owner'
    and pm.user_id is not null
  limit 1
)
where t.created_by is null;

drop policy if exists tasks_select_member on public.maintenance_tasks;
create policy tasks_select_member on public.maintenance_tasks
  for select
  using (created_by = auth.uid() or public.is_task_assignee(property_id, assignee_ids));

drop policy if exists tasks_insert_write on public.maintenance_tasks;
create policy tasks_insert_write on public.maintenance_tasks
  for insert
  with check (public.has_property_write_access(property_id) and created_by = auth.uid());

drop policy if exists tasks_update_write on public.maintenance_tasks;
create policy tasks_update_write on public.maintenance_tasks
  for update
  using (created_by = auth.uid())
  with check (created_by = auth.uid());

drop policy if exists tasks_delete_owner on public.maintenance_tasks;
create policy tasks_delete_owner on public.maintenance_tasks
  for delete
  using (created_by = auth.uid() or public.is_property_owner_or_partner(property_id));
