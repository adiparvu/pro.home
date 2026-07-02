-- 089 — role-based RLS, phase 3 (part 1): helpers + finances
--
-- Until now most modules used the binary is_property_member() — any member sees
-- everything. This begins scoping by role. Two helpers, then the finances
-- module (the most sensitive) is restricted to the "household adult" tier.
--
-- Tiers:
--   household adults : owner, partner, family_adult, family_elderly  → full home
--   limited          : family_child, family_teen                     → no finances
--   scoped           : tenant, service_provider                      → own data only
--   chat-only        : guest
--
-- Safe to apply now: the only members that exist are owners, so preserving
-- owner access changes nothing today and correctly scopes future invitees.

create or replace function public.member_role(p_property_id uuid)
returns public.user_role
language sql stable security definer
set search_path = public
as $$
  select role
  from public.property_members
  where property_id = p_property_id
    and user_id = auth.uid()
    and status = 'active'
  limit 1;
$$;

-- Trusted household adults — see the whole home (finances, etc.).
create or replace function public.has_household_access(p_property_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce(
    public.member_role(p_property_id)
      in ('owner', 'partner', 'family_adult', 'family_elderly'),
    false);
$$;

grant execute on function public.member_role(uuid) to authenticated;
grant execute on function public.has_household_access(uuid) to authenticated;

-- ── Finances: household adults only ─────────────────────────────────────────

drop policy if exists financial_select_member on public.financial_records;
create policy financial_select_member on public.financial_records
  for select using (public.has_household_access(property_id));

drop policy if exists "Members can view property budgets" on public.property_budgets;
create policy "Members can view property budgets" on public.property_budgets
  for select using (public.has_household_access(property_id));

drop policy if exists "Members can manage property budgets" on public.property_budgets;
create policy "Members can manage property budgets" on public.property_budgets
  for all using (public.has_household_access(property_id))
  with check (public.has_household_access(property_id));

-- Security fix: receipts had a blanket `true` policy — any authenticated user
-- could read/modify every receipt. Scope to the property's household adults.
drop policy if exists receipts_all on public.receipts;
create policy receipts_select on public.receipts
  for select using (public.has_household_access(property_id));
create policy receipts_write on public.receipts
  for all using (public.is_property_owner_or_partner(property_id))
  with check (public.is_property_owner_or_partner(property_id));
