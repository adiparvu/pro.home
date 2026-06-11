-- Migration 031: Property Analytics tables
-- property_shares
create table if not exists property_shares (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  owner_name text not null,
  share_percentage numeric(5,2) not null check (share_percentage > 0 and share_percentage <= 100),
  ownership_type text default 'freehold' check (ownership_type in ('freehold', 'leasehold', 'shared_ownership')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table property_shares enable row level security;
create policy "property_members_property_shares" on property_shares
  using (exists (
    select 1 from property_members pm
    where pm.property_id = property_shares.property_id
      and pm.user_id = (select auth.uid())
      and pm.status = 'active'
  ));

-- property_valuations
create table if not exists property_valuations (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  valuation_date date not null,
  estimated_value numeric(12,2) not null,
  currency text not null default 'RON',
  source text default 'manual' check (source in ('manual', 'agent', 'automated', 'survey')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table property_valuations enable row level security;
create policy "property_members_property_valuations" on property_valuations
  using (exists (
    select 1 from property_members pm
    where pm.property_id = property_valuations.property_id
      and pm.user_id = (select auth.uid())
      and pm.status = 'active'
  ));

-- property_health_history
create table if not exists property_health_history (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  recorded_at timestamptz not null default now(),
  overall_score int check (overall_score between 0 and 100),
  maintenance_score int check (maintenance_score between 0 and 100),
  financial_score int check (financial_score between 0 and 100),
  compliance_score int check (compliance_score between 0 and 100),
  occupancy_score int check (occupancy_score between 0 and 100),
  notes jsonb,
  created_at timestamptz not null default now()
);
alter table property_health_history enable row level security;
create policy "property_members_property_health_history" on property_health_history
  using (exists (
    select 1 from property_members pm
    where pm.property_id = property_health_history.property_id
      and pm.user_id = (select auth.uid())
      and pm.status = 'active'
  ));

-- neighbourhood_benchmarks
create table if not exists neighbourhood_benchmarks (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  metric text not null,
  area_value numeric(12,2),
  own_value numeric(12,2),
  unit text,
  source text,
  recorded_date date not null default current_date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table neighbourhood_benchmarks enable row level security;
create policy "property_members_neighbourhood_benchmarks" on neighbourhood_benchmarks
  using (exists (
    select 1 from property_members pm
    where pm.property_id = neighbourhood_benchmarks.property_id
      and pm.user_id = (select auth.uid())
      and pm.status = 'active'
  ));

-- carbon_settings
create table if not exists carbon_settings (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  heating_type text default 'gas' check (heating_type in ('gas', 'electric', 'heat_pump', 'district', 'oil', 'biomass', 'other')),
  epc_rating text check (epc_rating in ('A', 'B', 'C', 'D', 'E', 'F', 'G')),
  epc_expiry date,
  solar_panels boolean not null default false,
  solar_capacity_kw numeric(6,2),
  ev_charger boolean not null default false,
  insulation_rating text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(property_id)
);
alter table carbon_settings enable row level security;
create policy "property_members_carbon_settings" on carbon_settings
  using (exists (
    select 1 from property_members pm
    where pm.property_id = carbon_settings.property_id
      and pm.user_id = (select auth.uid())
      and pm.status = 'active'
  ));
