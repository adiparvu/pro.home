-- 109: Expired suspensions count as active in ALL access helpers, not just
-- member_role — otherwise a member whose block lapsed could read tasks (via
-- has_household_access → member_role) but not the member list.

create or replace function public.is_property_member(p_property_id uuid)
returns boolean
language sql stable security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from public.property_members
    where property_id = p_property_id
      and user_id = auth.uid()
      and (status = 'active'
           or (status = 'suspended' and blocked_until is not null and blocked_until <= now()))
  );
$$;

create or replace function public.is_property_owner_or_partner(p_property_id uuid)
returns boolean
language sql stable security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from public.property_members
    where property_id = p_property_id
      and user_id = auth.uid()
      and (status = 'active'
           or (status = 'suspended' and blocked_until is not null and blocked_until <= now()))
      and role in ('owner', 'partner')
  );
$$;
