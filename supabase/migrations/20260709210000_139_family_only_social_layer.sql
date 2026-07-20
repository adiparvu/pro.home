-- 139: The social layer belongs to the family.
--
-- The owner's model: the family core (owner, partner, family_*) shares the
-- house's life; outsiders (tenant, guest, service_provider) have strictly
-- their own things and communicate through DMs or groups they were explicitly
-- added to. Until now every ACTIVE MEMBER — including tenants, workers and
-- guests — could read the family's main chat, stories, who's online, the full
-- member roster and every group's name. This migration closes that.
--
-- DMs are untouched: they live in direct_messages with a sender/recipient
-- policy that is already correct.

-- ── Main chat: family only. Groups: explicit members only. ──────────────────
drop policy if exists messages_select on public.messages;
create policy messages_select on public.messages
  for select using (
    sender_id = auth.uid()
    or (group_id is null     and public.has_family_access(property_id))
    or (group_id is not null and public.is_chat_group_member(group_id, auth.uid()))
  );

drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages
  for insert with check (
    sender_id = auth.uid()
    and (
      (group_id is null     and public.has_family_access(property_id))
      or (group_id is not null and public.is_chat_group_member(group_id, auth.uid()))
    )
  );

-- ── Reactions follow the message's visibility ────────────────────────────────
drop policy if exists reactions_select_member on public.message_reactions;
create policy reactions_select_member on public.message_reactions
  for select using (
    public.has_family_access(property_id)
    or exists (
      select 1 from public.messages m
      where m.id = message_reactions.message_id
        and m.group_id is not null
        and public.is_chat_group_member(m.group_id, auth.uid())
    )
  );

drop policy if exists reactions_insert_own on public.message_reactions;
create policy reactions_insert_own on public.message_reactions
  for insert with check (
    user_id = (select auth.uid())
    and (
      public.has_family_access(property_id)
      or exists (
        select 1 from public.messages m
        where m.id = message_reactions.message_id
          and m.group_id is not null
          and public.is_chat_group_member(m.group_id, auth.uid())
      )
    )
  );

-- ── Presence (who's online) is family-private ───────────────────────────────
drop policy if exists members_select on public.presence;
create policy members_select on public.presence
  for select using (public.has_family_access(property_id));

-- ── Stories are family-private ───────────────────────────────────────────────
drop policy if exists members_select on public.status_updates;
create policy members_select on public.status_updates
  for select using (public.has_family_access(property_id));

drop policy if exists author_insert on public.status_updates;
create policy author_insert on public.status_updates
  for insert with check (public.has_family_access(property_id) and author_id = auth.uid());

drop policy if exists viewer_select on public.status_views;
create policy viewer_select on public.status_views
  for select using (exists (
    select 1 from public.status_updates s
    where s.id = status_views.status_id and public.has_family_access(s.property_id)
  ));

drop policy if exists viewer_insert on public.status_views;
create policy viewer_insert on public.status_views
  for insert with check (
    viewer_id = auth.uid()
    and exists (
      select 1 from public.status_updates s
      where s.id = status_views.status_id and public.has_family_access(s.property_id)
    )
  );

-- ── Groups: family sees the property's groups; an outsider sees ONLY groups
--    they're a member of (not even the names of the others). ─────────────────
drop policy if exists groups_select on public.chat_groups;
create policy groups_select on public.chat_groups
  for select using (
    public.has_family_access(property_id)
    or public.is_chat_group_member(id, auth.uid())
  );

drop policy if exists group_members_select on public.chat_group_members;
create policy group_members_select on public.chat_group_members
  for select using (
    exists (
      select 1 from public.chat_groups g
      where g.id = chat_group_members.group_id
        and public.has_family_access(g.property_id)
    )
    or public.is_chat_group_member(group_id, auth.uid())
  );

-- ── Member roster: family sees everyone; an outsider sees the contact
--    persons (owner/partner) and themselves — enough to start a DM. ──────────
drop policy if exists members_select_property_member on public.property_members;
create policy members_select_property_member on public.property_members
  for select using (
    public.has_family_access(property_id)
    or user_id = auth.uid()
    or role in ('owner', 'partner')
  );

-- ── Chat plumbing scoped the same way ───────────────────────────────────────
drop policy if exists chat_disappear_select on public.chat_disappear_settings;
create policy chat_disappear_select on public.chat_disappear_settings
  for select using (
    public.has_family_access(property_id)
    or exists (
      select 1 from public.chat_groups g
      where g.id::text = chat_disappear_settings.conv_key
        and public.is_chat_group_member(g.id, auth.uid())
    )
  );

drop policy if exists chat_disappear_insert on public.chat_disappear_settings;
create policy chat_disappear_insert on public.chat_disappear_settings
  for insert with check (public.has_family_access(property_id));

drop policy if exists chat_disappear_update on public.chat_disappear_settings;
create policy chat_disappear_update on public.chat_disappear_settings
  for update using (public.has_family_access(property_id));

drop policy if exists chat_disappear_delete on public.chat_disappear_settings;
create policy chat_disappear_delete on public.chat_disappear_settings
  for delete using (public.has_family_access(property_id));

drop policy if exists members_rw on public.chat_group_settings;
create policy members_rw on public.chat_group_settings
  for all using (public.has_family_access(property_id))
  with check (public.has_family_access(property_id));

drop policy if exists members_rw on public.chat_member_labels;
create policy members_rw on public.chat_member_labels
  for all using (public.has_family_access(property_id))
  with check (public.has_family_access(property_id));

-- ── Plants are household things; outsiders have no business writing them ────
drop policy if exists plant_automations_access on public.plant_automations;
create policy plant_automations_access on public.plant_automations
  for all using (public.has_family_access(property_id))
  with check (public.has_family_access(property_id));

drop policy if exists plant_events_access on public.plant_events;
create policy plant_events_access on public.plant_events
  for all using (public.has_family_access(property_id))
  with check (public.has_family_access(property_id));

drop policy if exists plant_photos_access on public.plant_photos;
create policy plant_photos_access on public.plant_photos
  for all using (public.has_family_access(property_id))
  with check (public.has_family_access(property_id));

drop policy if exists plant_sensors_access on public.plant_sensors;
create policy plant_sensors_access on public.plant_sensors
  for all using (public.has_family_access(property_id))
  with check (public.has_family_access(property_id));

-- ── Audit trail: your own entries, plus household adults see the house's ────
drop policy if exists audit_logs_select_member on public.audit_logs;
create policy audit_logs_select_member on public.audit_logs
  for select using (
    user_id = auth.uid()
    or (property_id is not null and public.has_household_access(property_id))
  );
