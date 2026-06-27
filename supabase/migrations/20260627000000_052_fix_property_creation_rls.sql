-- 052: Fix the RLS bootstrap deadlock that blocked creating a new property.
--
-- Symptom: "new row violates row-level security policy for table 'properties'".
-- Cause: PropertyService.create() does INSERT ... RETURNING. After the insert,
-- the creator is not yet a property_member, so the SELECT policy
-- (is_property_member) failed on the RETURNING row; and inserting the owner
-- membership was itself blocked by is_property_owner_or_partner. Classic
-- bootstrap deadlock. We let creator_id stand in for membership and
-- auto-create the owner membership server-side.

-- 1. Creator can always SELECT their property (needed for INSERT ... RETURNING).
drop policy if exists properties_select_member on public.properties;
create policy properties_select_member on public.properties
  for select using (is_property_member(id) or creator_id = auth.uid());

-- 2. Creator can UPDATE their property.
drop policy if exists properties_update_owner on public.properties;
create policy properties_update_owner on public.properties
  for update using (is_property_owner_or_partner(id) or creator_id = auth.uid())
  with check (is_property_owner_or_partner(id) or creator_id = auth.uid());

-- 3. Creator can DELETE their property.
drop policy if exists properties_delete_owner on public.properties;
create policy properties_delete_owner on public.properties
  for delete using (is_property_owner_or_partner(id) or creator_id = auth.uid());

-- 4. Creator can insert their own membership rows (before any owner exists).
drop policy if exists members_insert_owner on public.property_members;
create policy members_insert_owner on public.property_members
  for insert with check (
    is_property_owner_or_partner(property_id)
    or exists (
      select 1 from public.properties p
      where p.id = property_id and p.creator_id = auth.uid()
    )
  );

-- 5. Auto-create the creator's owner membership on every new property.
create or replace function public.add_creator_as_owner()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.creator_id is not null then
    insert into public.property_members (property_id, user_id, role, status)
    values (new.id, new.creator_id, 'owner', 'active')
    on conflict (property_id, user_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists properties_add_creator_member on public.properties;
create trigger properties_add_creator_member
  after insert on public.properties
  for each row execute function public.add_creator_as_owner();
