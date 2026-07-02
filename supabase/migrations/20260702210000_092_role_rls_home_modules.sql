-- 092 — role-based RLS, phase 3 (part 4): the rest of the home modules
--
-- Digital twin (elements/zones/rooms/automations/floor plans/health), energy,
-- garden, security, live locations, marketplace and service requests were all
-- readable by any member (is_property_member) — including guests. They become
-- family data (has_family_access): family sees them; tenants, workers and
-- guests do not. This completes "friend = chat only".
--
-- Chat tables (messages, presence, chat_groups, status, reactions, …) are
-- intentionally left on is_property_member — every member, guests included,
-- may use chat. Write policies are unchanged; only read scope narrows.

-- Digital twin
drop policy if exists property_elements_select on public.property_elements;
create policy property_elements_select on public.property_elements
  for select using (public.has_family_access(property_id));

drop policy if exists property_zones_select on public.property_zones;
create policy property_zones_select on public.property_zones
  for select using (public.has_family_access(property_id));

drop policy if exists rooms_select_member on public.rooms;
create policy rooms_select_member on public.rooms
  for select using (public.has_family_access(property_id));

drop policy if exists floor_plans_select on public.floor_plans;
create policy floor_plans_select on public.floor_plans
  for select using (public.has_family_access(property_id));

drop policy if exists health_select_member on public.health_scores;
create policy health_select_member on public.health_scores
  for select using (public.has_family_access(property_id));

drop policy if exists element_automations_select on public.element_automations;
create policy element_automations_select on public.element_automations
  for select using (public.has_family_access(property_id));

drop policy if exists element_notes_select on public.element_notes;
create policy element_notes_select on public.element_notes
  for select using (public.has_family_access(property_id));

drop policy if exists element_records_select on public.element_records;
create policy element_records_select on public.element_records
  for select using (public.has_family_access(property_id));

drop policy if exists property_automations_select on public.property_automations;
create policy property_automations_select on public.property_automations
  for select using (public.has_family_access(property_id));

-- Energy
drop policy if exists energy_select on public.energy_readings;
create policy energy_select on public.energy_readings
  for select using (public.has_family_access(property_id));

-- Garden
drop policy if exists garden_plants_select on public.garden_plants;
create policy garden_plants_select on public.garden_plants
  for select using (public.has_family_access(property_id));

drop policy if exists garden_zones_select on public.garden_zones;
create policy garden_zones_select on public.garden_zones
  for select using (public.has_family_access(property_id));

-- Security
drop policy if exists security_events_select on public.security_events;
create policy security_events_select on public.security_events
  for select using (public.has_family_access(property_id));

drop policy if exists security_state_select on public.security_state;
create policy security_state_select on public.security_state
  for select using (public.has_family_access(property_id));

-- Live locations (read; the per-user insert/update/delete policies are unchanged)
drop policy if exists members_select on public.live_locations;
create policy members_select on public.live_locations
  for select using (public.has_family_access(property_id));

-- Marketplace + service requests (were blanket ALL for any member)
drop policy if exists marketplace_contacts_property_member on public.marketplace_contacts;
create policy marketplace_contacts_property_member on public.marketplace_contacts
  for all using (public.has_family_access(property_id))
  with check (public.has_family_access(property_id));

drop policy if exists service_requests_property_member on public.service_requests;
create policy service_requests_property_member on public.service_requests
  for all using (public.has_family_access(property_id))
  with check (public.has_family_access(property_id));
