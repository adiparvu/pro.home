-- 100 — Security hardening, Batch 5 (medium findings + DB hygiene)
--
-- 1. Three tables had "always true" RLS, i.e. no protection at all:
--    - household_budgets: any authenticated user could read/write any
--      property's budgets. Scope to the household (owner/partner write).
--    - receipt_items: same — scope to the household.
--    - tenant_requests: the public INSERT path (a tenant submitting a request
--      through their portal) allowed inserting a request for ANY property_id.
--      Require the referenced portal to actually belong to that property.
-- 2. Drop a duplicate index on custom_integrations (identical to the one the
--    097 migration declares).

-- ── household_budgets ───────────────────────────────────────────────────────

drop policy if exists household_budgets_all on public.household_budgets;

create policy household_budgets_read on public.household_budgets
  for select using (public.has_household_access(property_id));
create policy household_budgets_write on public.household_budgets
  for all
  using (public.member_role(property_id) in ('owner','partner'))
  with check (public.member_role(property_id) in ('owner','partner'));

-- ── receipt_items ───────────────────────────────────────────────────────────

drop policy if exists receipt_items_all on public.receipt_items;

create policy receipt_items_access on public.receipt_items
  for all
  using (public.has_household_access(property_id))
  with check (public.has_household_access(property_id));

-- ── tenant_requests: validate the portal on public insert ───────────────────
--
-- A tenant submitting through a portal is not a property member, so the check
-- can't use has_household_access. This SECURITY DEFINER helper confirms the
-- portal exists and belongs to the claimed property, bypassing tenant_portals'
-- (owner/partner-only) RLS while exposing just a boolean.

create or replace function public.portal_belongs_to_property(p_portal_id uuid, p_property_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.tenant_portals tp
    where tp.id = p_portal_id
      and tp.property_id = p_property_id
  );
$$;

drop policy if exists tenant_requests_public_insert on public.tenant_requests;
create policy tenant_requests_public_insert on public.tenant_requests
  for insert
  with check (public.portal_belongs_to_property(portal_id, property_id));

-- ── DB hygiene: drop the duplicate index ────────────────────────────────────

drop index if exists public.custom_integrations_property;
