-- 093 — role-based RLS, phase 3 (part 5): stragglers
--
-- Two gaps left after 092:
--   1. garden_tasks read still used is_property_member (guests could see it).
--   2. automations/notes UPDATE+DELETE used is_property_member — ANY member,
--      including a guest, could modify home config. Scope writes to family.

drop policy if exists garden_tasks_select on public.garden_tasks;
create policy garden_tasks_select on public.garden_tasks
  for select using (public.has_family_access(property_id));

drop policy if exists element_automations_update on public.element_automations;
create policy element_automations_update on public.element_automations
  for update using (public.has_family_access(property_id))
  with check (public.has_family_access(property_id));
drop policy if exists element_automations_delete on public.element_automations;
create policy element_automations_delete on public.element_automations
  for delete using (public.has_family_access(property_id));

drop policy if exists element_notes_update on public.element_notes;
create policy element_notes_update on public.element_notes
  for update using (public.has_family_access(property_id))
  with check (public.has_family_access(property_id));
drop policy if exists element_notes_delete on public.element_notes;
create policy element_notes_delete on public.element_notes
  for delete using (public.has_family_access(property_id));

drop policy if exists property_automations_update on public.property_automations;
create policy property_automations_update on public.property_automations
  for update using (public.has_family_access(property_id))
  with check (public.has_family_access(property_id));
drop policy if exists property_automations_delete on public.property_automations;
create policy property_automations_delete on public.property_automations
  for delete using (public.has_family_access(property_id));
