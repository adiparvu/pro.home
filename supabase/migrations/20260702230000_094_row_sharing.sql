-- 094 — per-row sharing: bills/documents for a specific scoped member
--
-- A tenant/worker can't see finances or all documents (091/089). This lets an
-- owner share a *specific* row with a member: shared_member_ids holds
-- family_members.id strings (same convention as maintenance_tasks.assignee_ids).
-- The shared member then sees exactly that row, nothing else.

alter table public.financial_records
  add column if not exists shared_member_ids text[] not null default '{}';
alter table public.documents
  add column if not exists shared_member_ids text[] not null default '{}';

-- SECURITY DEFINER (family_members has its own owner-scoped RLS — an inline
-- subquery in the policy would find nothing for the shared member).
create or replace function public.is_shared_with_me(p_property_id uuid, p_shared_ids text[])
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce(exists (
    select 1 from public.family_members fm
    where fm.user_id = auth.uid()
      and fm.property_id = p_property_id
      and fm.id::text = any(p_shared_ids)
  ), false);
$$;

grant execute on function public.is_shared_with_me(uuid, text[]) to authenticated;

-- Finances: household adults, OR a member this row is shared with.
drop policy if exists financial_select_member on public.financial_records;
create policy financial_select_member on public.financial_records
  for select using (
    public.has_household_access(property_id)
    or public.is_shared_with_me(property_id, shared_member_ids)
  );

-- Documents: family, OR a member this doc is shared with.
drop policy if exists documents_select_member on public.documents;
create policy documents_select_member on public.documents
  for select using (
    public.has_family_access(property_id)
    or public.is_shared_with_me(property_id, shared_member_ids)
  );
