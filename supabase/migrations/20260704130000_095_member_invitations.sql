-- 095 — member invitations: tracking + management RPCs
--
-- The invite edge function creates the auth user and membership immediately,
-- but nothing recorded WHO was invited WHEN, or until when the invite link is
-- valid. This table is the audit trail the Members hub lists; the RPCs are
-- SECURITY DEFINER because they must join auth.users (accepted = the invitee
-- actually signed in) and manage property_members rows the caller's RLS can't.

create table if not exists public.member_invitations (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  email text not null,
  name text,
  role text not null default 'guest',
  invited_by uuid not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  revoked_at timestamptz
);

create unique index if not exists member_invitations_prop_email
  on public.member_invitations (property_id, lower(email));

alter table public.member_invitations enable row level security;

drop policy if exists member_invitations_select on public.member_invitations;
create policy member_invitations_select on public.member_invitations
  for select using (public.has_household_access(property_id));

create or replace function public.list_member_invitations(p_property_id uuid)
returns table (
  id uuid, email text, name text, role text,
  created_at timestamptz, expires_at timestamptz,
  revoked_at timestamptz, accepted boolean
)
language sql stable security definer
set search_path = public
as $$
  select mi.id, mi.email, mi.name, mi.role,
         mi.created_at, mi.expires_at, mi.revoked_at,
         (u.last_sign_in_at is not null) as accepted
  from public.member_invitations mi
  left join auth.users u on lower(u.email) = lower(mi.email)
  where mi.property_id = p_property_id
    and public.member_role(p_property_id) in ('owner', 'partner')
  order by mi.created_at desc;
$$;

grant execute on function public.list_member_invitations(uuid) to authenticated;

create or replace function public.revoke_member_invitation(p_invitation_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  inv record;
  target uuid;
begin
  select * into inv from public.member_invitations where id = p_invitation_id;
  if inv is null then raise exception 'invitation not found'; end if;
  if public.member_role(inv.property_id) not in ('owner', 'partner') then
    raise exception 'not allowed';
  end if;

  update public.member_invitations set revoked_at = now() where id = p_invitation_id;

  select u.id into target from auth.users u where lower(u.email) = lower(inv.email);
  if target is not null then
    delete from public.property_members
      where property_id = inv.property_id and user_id = target and role <> 'owner';
    update public.family_members set user_id = null
      where property_id = inv.property_id and user_id = target;
  end if;
end;
$$;

grant execute on function public.revoke_member_invitation(uuid) to authenticated;

create or replace function public.remove_property_member(p_family_member_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  fm record;
begin
  select * into fm from public.family_members where id = p_family_member_id;
  if fm is null then raise exception 'member not found'; end if;
  if public.member_role(fm.property_id) not in ('owner', 'partner') then
    raise exception 'not allowed';
  end if;

  if fm.user_id is not null then
    delete from public.property_members
      where property_id = fm.property_id and user_id = fm.user_id and role <> 'owner';
  end if;
  delete from public.family_members where id = p_family_member_id;
  if fm.email is not null then
    update public.member_invitations set revoked_at = coalesce(revoked_at, now())
      where property_id = fm.property_id and lower(email) = lower(fm.email);
  end if;
end;
$$;

grant execute on function public.remove_property_member(uuid) to authenticated;
