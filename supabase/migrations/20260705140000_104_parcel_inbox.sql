-- 104 — parcel inbox (auto-import deliveries from forwarded shipping emails)
--
-- Each property gets a unique forwarding address (e.g. <token>@parcels.<domain>).
-- The user sets a Gmail filter to auto-forward courier/shop shipping emails to
-- it; an inbound-email provider POSTs them to the `email-inbound` Edge Function,
-- which looks the token up here to know which property the parcel belongs to,
-- extracts the tracking number, creates the delivery and registers it for live
-- tracking. The token is the only routing secret, so it's random + revocable.

create table if not exists public.parcel_inbox (
  id          uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  token       text not null unique,      -- local-part of the forwarding address
  created_by  uuid,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create index if not exists parcel_inbox_property_idx on public.parcel_inbox(property_id);
create index if not exists parcel_inbox_token_idx on public.parcel_inbox(token);

alter table public.parcel_inbox enable row level security;

-- Household members can see and manage their property's forwarding address.
drop policy if exists parcel_inbox_read on public.parcel_inbox;
create policy parcel_inbox_read on public.parcel_inbox
  for select using (public.has_household_access(property_id));

drop policy if exists parcel_inbox_insert on public.parcel_inbox;
create policy parcel_inbox_insert on public.parcel_inbox
  for insert with check (public.has_household_access(property_id));

drop policy if exists parcel_inbox_update on public.parcel_inbox;
create policy parcel_inbox_update on public.parcel_inbox
  for update using (public.has_household_access(property_id));

drop policy if exists parcel_inbox_delete on public.parcel_inbox;
create policy parcel_inbox_delete on public.parcel_inbox
  for delete using (public.has_household_access(property_id));

comment on table public.parcel_inbox is 'Per-property forwarding address for auto-importing deliveries from shipping emails.';
