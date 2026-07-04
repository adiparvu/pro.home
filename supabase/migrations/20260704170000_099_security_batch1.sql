-- 099 — Security hardening, Batch 1 (critical access-control fixes)
--
-- Four fixes from the full security audit:
--   1. direct_messages RLS was keyed on the caller's *display name*, which is
--      user-editable and non-unique — anyone could rename themselves to a
--      victim and read/edit/delete that victim's DMs. Re-key on immutable
--      identity: sender_id = auth.uid() for the sender, and the recipient's
--      linked account (family_members.user_id) for the recipient.
--   2. smart_home_tokens / temp_access_codes / tenant_portals exposed secret
--      device tokens and physical access codes to *any* active member of any
--      role (a guest, child, tenant or contractor). Restrict to owner/partner.
--   3. outbound_webhooks had a broad active-any-role ALL policy sitting next to
--      the correct owner/partner policies, nullifying them. Drop the broad one.
--   4. cross_app_channels / custom_integrations exposed their secret inbound
--      tokens to every household adult. Restrict SELECT to owner/partner.
--
-- direct_messages is empty and unreleased, so the DM change is a clean re-key
-- with no data migration.

-- ── 1. direct_messages: identity-based RLS ───────────────────────────────────

-- family_members is only SELECT-able by the property owner (owner_id = auth.uid),
-- so an `exists(select from family_members …)` inside a policy would be filtered
-- by that RLS and the recipient could never see their own DMs. This SECURITY
-- DEFINER helper resolves "is the caller the account linked to this member?"
-- while bypassing family_members' RLS, exposing only a boolean.
create or replace function public.is_my_family_member(p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.family_members
    where id = p_member_id
      and user_id = auth.uid()
  );
$$;
revoke execute on function public.is_my_family_member(uuid) from anon;

drop policy if exists dm_select on public.direct_messages;
drop policy if exists dm_update on public.direct_messages;
drop policy if exists dm_delete on public.direct_messages;
drop policy if exists dm_insert on public.direct_messages;

-- A caller is a party to the DM iff they are the sender (sender_id) or the
-- recipient's linked account owns the recipient family_members row.
create policy dm_select on public.direct_messages
  for select to authenticated
  using (
    sender_id = auth.uid()
    or public.is_my_family_member(recipient_member_id)
  );

-- Either party may update (read receipts, edit, pin, react, soft-delete).
create policy dm_update on public.direct_messages
  for update to authenticated
  using (
    sender_id = auth.uid()
    or public.is_my_family_member(recipient_member_id)
  )
  with check (
    sender_id = auth.uid()
    or public.is_my_family_member(recipient_member_id)
  );

-- Only the sender may hard-delete their own message.
create policy dm_delete on public.direct_messages
  for delete to authenticated
  using (sender_id = auth.uid());

-- Insert: the sender must be the authenticated user, and must not be blocked
-- by the recipient. (Block list is still name-based; preserved as-is.)
create policy dm_insert on public.direct_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and not exists (
      select 1 from public.chat_blocks b
      where b.blocker_name = direct_messages.recipient_name
        and b.blocked_name = direct_messages.sender_name
    )
  );

-- ── 2. Secret token / access-code tables: owner/partner only ────────────────

-- smart_home_tokens
drop policy if exists property_members_smart_home_tokens on public.smart_home_tokens;
drop policy if exists smart_home_tokens_member on public.smart_home_tokens;
create policy smart_home_tokens_managers on public.smart_home_tokens
  for all to authenticated
  using (public.member_role(property_id) in ('owner','partner'))
  with check (public.member_role(property_id) in ('owner','partner'));

-- temp_access_codes
drop policy if exists "member access" on public.temp_access_codes;
drop policy if exists property_members_temp_access_codes on public.temp_access_codes;
create policy temp_access_codes_managers on public.temp_access_codes
  for all to authenticated
  using (public.member_role(property_id) in ('owner','partner'))
  with check (public.member_role(property_id) in ('owner','partner'));

-- tenant_portals (holds access_token)
drop policy if exists property_members_tenant_portals on public.tenant_portals;
drop policy if exists tenant_portals_member on public.tenant_portals;
create policy tenant_portals_managers on public.tenant_portals
  for all to authenticated
  using (public.member_role(property_id) in ('owner','partner'))
  with check (public.member_role(property_id) in ('owner','partner'));

-- ── 3. outbound_webhooks: drop the broad policy, keep owner/partner ones ─────

drop policy if exists property_members_outbound_webhooks on public.outbound_webhooks;

-- ── 4. Inbound integration tokens: SELECT restricted to owner/partner ───────

drop policy if exists cross_app_select on public.cross_app_channels;
create policy cross_app_select on public.cross_app_channels
  for select using (public.member_role(property_id) in ('owner','partner'));

drop policy if exists custom_integrations_select on public.custom_integrations;
create policy custom_integrations_select on public.custom_integrations
  for select using (public.member_role(property_id) in ('owner','partner'));
