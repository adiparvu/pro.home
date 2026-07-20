-- 163: household roster visibility (IMG_8614 — "Bianca nu vede membri")
--
-- family_members carried an owner-only SELECT policy from the untracked
-- baseline (documented in migration 099's comment: "family_members is only
-- SELECT-able by the property owner"), so EVERY non-owner — including the
-- owner's partner — saw an empty "Familie" page. The roster is household
-- information: anyone with family access may read it, and a linked account
-- may always see its own row. Writes stay owner-only (policies untouched).
--
-- The baseline policy's name is unknown (it predates tracked migrations),
-- so drop whatever SELECT policies exist on the table before recreating.

do $$
declare pol record;
begin
  for pol in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'family_members' and cmd = 'SELECT'
  loop
    execute format('drop policy %I on public.family_members', pol.policyname);
  end loop;
end $$;

create policy family_members_household_select on public.family_members
  for select using (
    owner_id = auth.uid()
    or user_id = auth.uid()
    or public.has_family_access(property_id)
  );
