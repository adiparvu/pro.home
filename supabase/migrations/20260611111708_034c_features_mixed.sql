-- Migration 034c: Mixed Features tables
-- compliance_certificates
create table if not exists compliance_certificates (
  id uuid primary key default gen_random_uuid(),
  property_id uuid references properties(id) on delete cascade,
  certificate_type text not null,
  issuer text, certificate_number text, issue_date date, expiry_date date,
  status text not null default 'valid' check (status in ('valid', 'expired', 'pending', 'not_required')),
  document_url text, notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table compliance_certificates add column if not exists property_id uuid references properties(id) on delete cascade;
alter table compliance_certificates enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='compliance_certificates' and policyname='property_members_compliance_certificates') then
    execute 'create policy "property_members_compliance_certificates" on compliance_certificates using (exists (select 1 from property_members pm where pm.property_id = compliance_certificates.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- contractors
create table if not exists contractors (
  id uuid primary key default gen_random_uuid(),
  property_id uuid references properties(id) on delete cascade,
  name text not null, company text, email text, phone text, trade text,
  rating int check (rating between 1 and 5),
  is_preferred boolean not null default false, notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table contractors add column if not exists property_id uuid references properties(id) on delete cascade;
alter table contractors enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='contractors' and policyname='property_members_contractors') then
    execute 'create policy "property_members_contractors" on contractors using (exists (select 1 from property_members pm where pm.property_id = contractors.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- contractor_messages
create table if not exists contractor_messages (
  id uuid primary key default gen_random_uuid(),
  contractor_id uuid references contractors(id) on delete cascade,
  property_id uuid references properties(id) on delete cascade,
  sender text not null default 'owner' check (sender in ('owner', 'contractor')),
  message text not null,
  sent_at timestamptz not null default now(), read_at timestamptz,
  created_at timestamptz not null default now()
);
alter table contractor_messages add column if not exists property_id uuid references properties(id) on delete cascade;
alter table contractor_messages add column if not exists contractor_id uuid references contractors(id) on delete cascade;
alter table contractor_messages enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='contractor_messages' and policyname='property_members_contractor_messages') then
    execute 'create policy "property_members_contractor_messages" on contractor_messages using (exists (select 1 from property_members pm where pm.property_id = contractor_messages.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- marketplace_contacts
create table if not exists marketplace_contacts (
  id uuid primary key default gen_random_uuid(),
  property_id uuid references properties(id) on delete cascade,
  listing_id text, contact_name text not null, contact_email text, contact_phone text, message text,
  status text not null default 'new' check (status in ('new', 'contacted', 'viewing_scheduled', 'offer_made', 'rejected', 'accepted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table marketplace_contacts add column if not exists property_id uuid references properties(id) on delete cascade;
alter table marketplace_contacts enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='marketplace_contacts' and policyname='property_members_marketplace_contacts') then
    execute 'create policy "property_members_marketplace_contacts" on marketplace_contacts using (exists (select 1 from property_members pm where pm.property_id = marketplace_contacts.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- meter_readings
create table if not exists meter_readings (
  id uuid primary key default gen_random_uuid(),
  property_id uuid references properties(id) on delete cascade,
  meter_type text not null check (meter_type in ('electricity', 'gas', 'water', 'heat', 'solar', 'other')),
  value numeric(12,3) not null,
  unit text not null default 'kWh',
  reading_date date not null default current_date,
  source text default 'manual' check (source in ('manual', 'smart_meter', 'estimate')),
  token_id uuid, notes text,
  created_at timestamptz not null default now()
);
alter table meter_readings add column if not exists property_id uuid references properties(id) on delete cascade;
alter table meter_readings enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='meter_readings' and policyname='property_members_meter_readings') then
    execute 'create policy "property_members_meter_readings" on meter_readings using (exists (select 1 from property_members pm where pm.property_id = meter_readings.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- projects
create table if not exists projects (
  id uuid primary key default gen_random_uuid(),
  property_id uuid references properties(id) on delete cascade,
  title text not null, description text,
  status text not null default 'planning' check (status in ('planning', 'in_progress', 'on_hold', 'completed', 'cancelled')),
  start_date date, end_date date,
  budget numeric(12,2), actual_cost numeric(12,2),
  currency text not null default 'RON', notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table projects add column if not exists property_id uuid references properties(id) on delete cascade;
alter table projects enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='projects' and policyname='property_members_projects') then
    execute 'create policy "property_members_projects" on projects using (exists (select 1 from property_members pm where pm.property_id = projects.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- packages
create table if not exists packages (
  id uuid primary key default gen_random_uuid(),
  property_id uuid references properties(id) on delete cascade,
  tracking_number text, carrier text, description text, sender text,
  status text not null default 'expected' check (status in ('expected', 'delivered', 'collected', 'returned')),
  expected_date date, delivered_at timestamptz, collected_at timestamptz, notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table packages add column if not exists property_id uuid references properties(id) on delete cascade;
alter table packages enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='packages' and policyname='property_members_packages') then
    execute 'create policy "property_members_packages" on packages using (exists (select 1 from property_members pm where pm.property_id = packages.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- household_lists
create table if not exists household_lists (
  id uuid primary key default gen_random_uuid(),
  property_id uuid references properties(id) on delete cascade,
  title text not null,
  list_type text not null default 'shopping' check (list_type in ('shopping', 'todo', 'inventory', 'other')),
  is_archived boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table household_lists add column if not exists property_id uuid references properties(id) on delete cascade;
alter table household_lists enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='household_lists' and policyname='property_members_household_lists') then
    execute 'create policy "property_members_household_lists" on household_lists using (exists (select 1 from property_members pm where pm.property_id = household_lists.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- household_list_items
create table if not exists household_list_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid references household_lists(id) on delete cascade,
  property_id uuid references properties(id) on delete cascade,
  title text not null, quantity text, category text,
  is_checked boolean not null default false,
  checked_at timestamptz,
  checked_by uuid references auth.users(id) on delete set null,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table household_list_items add column if not exists property_id uuid references properties(id) on delete cascade;
alter table household_list_items add column if not exists list_id uuid references household_lists(id) on delete cascade;
alter table household_list_items enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='household_list_items' and policyname='property_members_household_list_items') then
    execute 'create policy "property_members_household_list_items" on household_list_items using (exists (select 1 from property_members pm where pm.property_id = household_list_items.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- service_requests
create table if not exists service_requests (
  id uuid primary key default gen_random_uuid(),
  property_id uuid references properties(id) on delete cascade,
  category text not null, title text not null, description text, requested_by text,
  status text not null default 'open' check (status in ('open', 'assigned', 'in_progress', 'completed', 'cancelled')),
  priority text not null default 'medium' check (priority in ('low', 'medium', 'high', 'urgent')),
  assigned_contractor_id uuid references contractors(id) on delete set null,
  scheduled_date date, completed_at timestamptz,
  estimated_cost numeric(12,2), actual_cost numeric(12,2),
  currency text not null default 'RON', notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table service_requests add column if not exists property_id uuid references properties(id) on delete cascade;
alter table service_requests enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='service_requests' and policyname='property_members_service_requests') then
    execute 'create policy "property_members_service_requests" on service_requests using (exists (select 1 from property_members pm where pm.property_id = service_requests.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;
