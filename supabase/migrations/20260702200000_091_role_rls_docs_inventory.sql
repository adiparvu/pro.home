-- 091 — role-based RLS, phase 3 (part 3): documents + inventory
--
-- These are "family" data: the whole family (adults + children) may view them,
-- but tenants, workers and guests may not. (supply_lists / supply_items are
-- already per-user via owner_id = auth.uid(), so they're left as-is.)
--
-- has_family_access = any family role. Distinct from has_household_access
-- (adults only) used for finances.

create or replace function public.has_family_access(p_property_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce(
    public.member_role(p_property_id) in
      ('owner', 'partner', 'family_adult', 'family_elderly',
       'family_child', 'family_teen'),
    false);
$$;

grant execute on function public.has_family_access(uuid) to authenticated;

drop policy if exists documents_select_member on public.documents;
create policy documents_select_member on public.documents
  for select using (public.has_family_access(property_id));

drop policy if exists inventory_select_member on public.inventory_items;
create policy inventory_select_member on public.inventory_items
  for select using (public.has_family_access(property_id));
