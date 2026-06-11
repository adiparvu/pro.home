-- Migration 029: Tenant & Rental tables
-- leases
create table if not exists leases (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  tenant_name text not null,
  tenant_email text,
  tenant_phone text,
  start_date date not null,
  end_date date,
  rent_amount numeric(12,2) not null,
  rent_currency text not null default 'RON',
  deposit_amount numeric(12,2),
  status text not null default 'active' check (status in ('active', 'expired', 'terminated', 'pending')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table leases enable row level security;
create policy "property_members_leases" on leases
  using (exists (
    select 1 from property_members pm
    where pm.property_id = leases.property_id
      and pm.user_id = (select auth.uid())
      and pm.status = 'active'
  ));

-- tenant_portals
create table if not exists tenant_portals (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  lease_id uuid references leases(id) on delete set null,
  tenant_email text not null,
  access_token text unique not null default encode(gen_random_bytes(32), 'hex'),
  is_active boolean not null default true,
  last_accessed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table tenant_portals enable row level security;
create policy "property_members_tenant_portals" on tenant_portals
  using (exists (
    select 1 from property_members pm
    where pm.property_id = tenant_portals.property_id
      and pm.user_id = (select auth.uid())
      and pm.status = 'active'
  ));

-- tenant_requests
create table if not exists tenant_requests (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  portal_id uuid references tenant_portals(id) on delete set null,
  category text not null default 'general',
  title text not null,
  description text,
  status text not null default 'open' check (status in ('open', 'in_progress', 'resolved', 'closed')),
  priority text not null default 'medium' check (priority in ('low', 'medium', 'high', 'urgent')),
  submitted_at timestamptz not null default now(),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table tenant_requests enable row level security;
create policy "property_members_tenant_requests" on tenant_requests
  using (exists (
    select 1 from property_members pm
    where pm.property_id = tenant_requests.property_id
      and pm.user_id = (select auth.uid())
      and pm.status = 'active'
  ));

-- rent_payments
create table if not exists rent_payments (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  lease_id uuid references leases(id) on delete set null,
  amount numeric(12,2) not null,
  currency text not null default 'RON',
  due_date date not null,
  paid_date date,
  status text not null default 'pending' check (status in ('pending', 'paid', 'partial', 'late', 'waived')),
  payment_method text,
  reference text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table rent_payments enable row level security;
create policy "property_members_rent_payments" on rent_payments
  using (exists (
    select 1 from property_members pm
    where pm.property_id = rent_payments.property_id
      and pm.user_id = (select auth.uid())
      and pm.status = 'active'
  ));

-- vacancies
create table if not exists vacancies (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  start_date date not null,
  end_date date,
  reason text,
  lost_income numeric(12,2),
  currency text not null default 'RON',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table vacancies enable row level security;
create policy "property_members_vacancies" on vacancies
  using (exists (
    select 1 from property_members pm
    where pm.property_id = vacancies.property_id
      and pm.user_id = (select auth.uid())
      and pm.status = 'active'
  ));

-- deposit_deductions
create table if not exists deposit_deductions (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  lease_id uuid references leases(id) on delete set null,
  amount numeric(12,2) not null,
  currency text not null default 'RON',
  reason text not null,
  description text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'disputed', 'paid')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table deposit_deductions enable row level security;
create policy "property_members_deposit_deductions" on deposit_deductions
  using (exists (
    select 1 from property_members pm
    where pm.property_id = deposit_deductions.property_id
      and pm.user_id = (select auth.uid())
      and pm.status = 'active'
  ));
