-- 108: Temporary member blocking. Owners/partners can suspend a member's
-- access for a period (or indefinitely); access returns automatically once
-- blocked_until passes, because member_role treats an expired suspension as
-- active again.

alter table public.property_members
  add column if not exists blocked_until timestamptz;

create or replace function public.member_role(p_property_id uuid)
returns user_role
language sql stable security definer
set search_path to 'public'
as $$
  select role
  from public.property_members
  where property_id = p_property_id
    and user_id = auth.uid()
    and (status = 'active'
         or (status = 'suspended' and blocked_until is not null and blocked_until <= now()))
  limit 1;
$$;

create or replace function public.block_property_member(p_member_id uuid, p_until timestamptz)
returns void
language plpgsql security definer
set search_path to 'public'
as $$
declare
  target public.property_members;
begin
  select * into target from public.property_members where id = p_member_id;
  if target.id is null then
    raise exception 'Member not found';
  end if;
  if not public.is_property_owner_or_partner(target.property_id) then
    raise exception 'Only the owner or partner can block members';
  end if;
  if target.role = 'owner' then
    raise exception 'The owner cannot be blocked';
  end if;
  if target.user_id = auth.uid() then
    raise exception 'You cannot block yourself';
  end if;
  update public.property_members
     set status = 'suspended', blocked_until = p_until, updated_at = now()
   where id = p_member_id;
end;
$$;

create or replace function public.unblock_property_member(p_member_id uuid)
returns void
language plpgsql security definer
set search_path to 'public'
as $$
declare
  target public.property_members;
begin
  select * into target from public.property_members where id = p_member_id;
  if target.id is null then
    raise exception 'Member not found';
  end if;
  if not public.is_property_owner_or_partner(target.property_id) then
    raise exception 'Only the owner or partner can unblock members';
  end if;
  update public.property_members
     set status = 'active', blocked_until = null, updated_at = now()
   where id = p_member_id;
end;
$$;

grant execute on function public.block_property_member(uuid, timestamptz) to authenticated;
grant execute on function public.unblock_property_member(uuid) to authenticated;
