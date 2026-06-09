-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 001: Auth, Roles & Permissions Foundation
-- ═══════════════════════════════════════════════════════════════════════════

-- Enable required extensions
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";
create extension if not exists "citext";

-- ─── Role System ────────────────────────────────────────────────────────────

create type user_role as enum (
  'owner',           -- Full control, all features
  'partner',         -- Co-owner, almost full access (Partner/Spouse)
  'family_adult',    -- Adult child / family member, limited write
  'family_teen',     -- Teen, curated access, safe content
  'family_child',    -- Child, read-only + fun features
  'family_elderly',  -- Elderly parent, simplified + emergency focused
  'tenant',          -- Renter, very limited access
  'guest',           -- Temporary access, minimal
  'service_provider' -- Contractor/cleaner, task-scoped
);

create type property_type as enum (
  'house',
  'apartment',
  'villa',
  'condo',
  'townhouse',
  'studio',
  'other'
);

create type heating_type as enum (
  'gas',
  'electric',
  'heat_pump',
  'oil',
  'wood',
  'district',
  'solar',
  'other'
);

create type member_status as enum (
  'active',
  'inactive',
  'pending_invite',
  'suspended'
);

create type invitation_status as enum (
  'pending',
  'accepted',
  'declined',
  'expired',
  'revoked'
);

-- ─── Profiles Table (extends Supabase auth.users) ───────────────────────────

create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  email         citext not null,
  full_name     text not null default '',
  display_name  text,
  avatar_url    text,
  phone         text,
  locale        text not null default 'en',
  timezone      text not null default 'UTC',
  theme         text not null default 'dark' check (theme in ('dark', 'light', 'auto')),
  motion_pref   text not null default 'full' check (motion_pref in ('full', 'reduced', 'none')),
  onboarding_completed boolean not null default false,
  onboarding_step      integer not null default 0,
  last_seen_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.profiles is 'User profile extending Supabase auth. One per auth user.';

-- ─── Properties Table ───────────────────────────────────────────────────────

create table public.properties (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  address_line1   text not null,
  address_line2   text,
  city            text not null,
  state_province  text,
  postal_code     text,
  country         text not null default 'RO',
  latitude        numeric(10, 7),
  longitude       numeric(10, 7),
  property_type   property_type not null default 'house',
  size_sqm        numeric(8, 2),
  year_built      smallint,
  year_renovated  smallint,
  num_rooms       smallint,
  num_bathrooms   smallint,
  num_floors      smallint default 1,
  heating_type    heating_type,
  photo_url       text,
  thumbnail_url   text,
  timezone        text not null default 'Europe/Bucharest',
  currency        text not null default 'EUR',
  is_active       boolean not null default true,
  health_score    smallint check (health_score >= 0 and health_score <= 100),
  health_updated_at timestamptz,
  metadata        jsonb not null default '{}',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table public.properties is 'Properties owned or managed by users.';

-- ─── Property Members Table ─────────────────────────────────────────────────

create table public.property_members (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references public.properties(id) on delete cascade,
  user_id       uuid references public.profiles(id) on delete set null,
  role          user_role not null default 'guest',
  status        member_status not null default 'active',
  nickname      text,           -- Optional display override
  color         text,           -- Family member color tag
  permissions   jsonb not null default '{}',  -- Module-level overrides
  invited_by    uuid references public.profiles(id),
  joined_at     timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  unique (property_id, user_id)
);

comment on table public.property_members is 'Maps users to properties with roles and permissions.';

-- ─── Property Invitations Table ─────────────────────────────────────────────

create table public.property_invitations (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references public.properties(id) on delete cascade,
  invited_by    uuid not null references public.profiles(id),
  email         citext not null,
  role          user_role not null default 'guest',
  token         text not null unique default encode(gen_random_bytes(32), 'hex'),
  status        invitation_status not null default 'pending',
  message       text,
  expires_at    timestamptz not null default (now() + interval '7 days'),
  accepted_at   timestamptz,
  created_at    timestamptz not null default now()
);

comment on table public.property_invitations is 'Pending invitations to join a property.';

-- ─── Audit Log ──────────────────────────────────────────────────────────────

create table public.audit_logs (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid references public.properties(id) on delete set null,
  user_id       uuid references public.profiles(id) on delete set null,
  action        text not null,
  resource_type text not null,
  resource_id   uuid,
  old_data      jsonb,
  new_data      jsonb,
  ip_address    inet,
  user_agent    text,
  created_at    timestamptz not null default now()
) partition by range (created_at);

-- Create initial partition for current year
create table public.audit_logs_2026 partition of public.audit_logs
  for values from ('2026-01-01') to ('2027-01-01');

create table public.audit_logs_2027 partition of public.audit_logs
  for values from ('2027-01-01') to ('2028-01-01');

comment on table public.audit_logs is 'Immutable audit trail for all significant actions.';

-- ─── Indexes ─────────────────────────────────────────────────────────────────

create index idx_profiles_email on public.profiles(email);
create index idx_properties_country on public.properties(country);
create index idx_properties_active on public.properties(is_active) where is_active = true;
create index idx_property_members_user on public.property_members(user_id);
create index idx_property_members_property on public.property_members(property_id);
create index idx_property_members_role on public.property_members(property_id, role);
create index idx_invitations_token on public.property_invitations(token) where status = 'pending';
create index idx_invitations_email on public.property_invitations(email) where status = 'pending';
create index idx_audit_logs_property on public.audit_logs(property_id, created_at desc);
create index idx_audit_logs_user on public.audit_logs(user_id, created_at desc);

-- ─── Updated-At Triggers ─────────────────────────────────────────────────────

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger properties_updated_at
  before update on public.properties
  for each row execute function public.set_updated_at();

create trigger property_members_updated_at
  before update on public.property_members
  for each row execute function public.set_updated_at();

-- ─── Helper Functions ────────────────────────────────────────────────────────

-- Get caller's role on a given property
create or replace function public.get_my_property_role(p_property_id uuid)
returns user_role
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

-- Check if caller is owner or partner of a given property
create or replace function public.is_property_owner_or_partner(p_property_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.property_members
    where property_id = p_property_id
      and user_id = auth.uid()
      and status = 'active'
      and role in ('owner', 'partner')
  );
$$;

-- Check write access (owner, partner, or family_adult)
create or replace function public.has_property_write_access(p_property_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.property_members
    where property_id = p_property_id
      and user_id = auth.uid()
      and status = 'active'
      and role in ('owner', 'partner', 'family_adult')
  );
$$;

-- Check any access (member check)
create or replace function public.is_property_member(p_property_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.property_members
    where property_id = p_property_id
      and user_id = auth.uid()
      and status = 'active'
  );
$$;

-- Auto-create profile on new user
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, avatar_url)
  values (
    new.id,
    new.email::citext,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─── Row Level Security ──────────────────────────────────────────────────────

alter table public.profiles enable row level security;
alter table public.properties enable row level security;
alter table public.property_members enable row level security;
alter table public.property_invitations enable row level security;
alter table public.audit_logs enable row level security;

-- Profiles: users can read their own profile + public fields of others
create policy "profiles_select_own"
  on public.profiles for select
  using (id = auth.uid());

create policy "profiles_update_own"
  on public.profiles for update
  using (id = auth.uid())
  with check (id = auth.uid());

-- Properties: members can read, owners/partners can write
create policy "properties_select_member"
  on public.properties for select
  using (public.is_property_member(id));

create policy "properties_insert_authenticated"
  on public.properties for insert
  with check (auth.uid() is not null);

create policy "properties_update_owner"
  on public.properties for update
  using (public.is_property_owner_or_partner(id));

create policy "properties_delete_owner"
  on public.properties for delete
  using (public.is_property_owner_or_partner(id));

-- Property members: members can see co-members, owners can manage
create policy "members_select_property_member"
  on public.property_members for select
  using (public.is_property_member(property_id));

create policy "members_insert_owner"
  on public.property_members for insert
  with check (public.is_property_owner_or_partner(property_id));

create policy "members_update_owner"
  on public.property_members for update
  using (public.is_property_owner_or_partner(property_id));

create policy "members_delete_owner"
  on public.property_members for delete
  using (public.is_property_owner_or_partner(property_id));

-- Invitations: members can view, owners can create
create policy "invitations_select_member"
  on public.property_invitations for select
  using (public.is_property_member(property_id) or email = (select email from public.profiles where id = auth.uid()));

create policy "invitations_insert_owner"
  on public.property_invitations for insert
  with check (public.is_property_owner_or_partner(property_id));

create policy "invitations_update_owner"
  on public.property_invitations for update
  using (public.is_property_owner_or_partner(property_id) or email = (select email from public.profiles where id = auth.uid()));

-- Audit logs: members can view their property logs
create policy "audit_logs_select_member"
  on public.audit_logs for select
  using (
    property_id is null or public.is_property_member(property_id)
  );

-- Only system functions can insert audit logs
create policy "audit_logs_insert_service"
  on public.audit_logs for insert
  with check (false);  -- Only via security definer functions
