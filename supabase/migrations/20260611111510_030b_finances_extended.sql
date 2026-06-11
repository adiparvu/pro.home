-- Migration 030b: Finances Extended tables
-- mortgages
create table if not exists mortgages (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  lender text not null,
  account_number text,
  original_amount numeric(12,2) not null,
  current_balance numeric(12,2),
  currency text not null default 'RON',
  interest_rate numeric(6,4),
  rate_type text default 'fixed' check (rate_type in ('fixed', 'variable', 'tracker')),
  monthly_payment numeric(12,2),
  start_date date,
  end_date date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table mortgages enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='mortgages' and policyname='property_members_mortgages') then
    execute 'create policy "property_members_mortgages" on mortgages using (exists (select 1 from property_members pm where pm.property_id = mortgages.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- insurance_policies
create table if not exists insurance_policies (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  provider text not null,
  policy_number text,
  type text not null default 'building' check (type in ('building', 'contents', 'landlord', 'combined', 'other')),
  premium_amount numeric(12,2),
  currency text not null default 'RON',
  payment_frequency text default 'annual' check (payment_frequency in ('monthly', 'quarterly', 'annual')),
  start_date date,
  end_date date,
  cover_amount numeric(12,2),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table insurance_policies enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='insurance_policies' and policyname='property_members_insurance_policies') then
    execute 'create policy "property_members_insurance_policies" on insurance_policies using (exists (select 1 from property_members pm where pm.property_id = insurance_policies.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- category_budgets
create table if not exists category_budgets (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  category text not null,
  year int not null,
  month int check (month between 1 and 12),
  budget_amount numeric(12,2) not null,
  currency text not null default 'RON',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table category_budgets enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='category_budgets' and policyname='property_members_category_budgets') then
    execute 'create policy "property_members_category_budgets" on category_budgets using (exists (select 1 from property_members pm where pm.property_id = category_budgets.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- cost_splits
create table if not exists cost_splits (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  title text not null,
  total_amount numeric(12,2) not null,
  currency text not null default 'RON',
  split_date date not null default current_date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table cost_splits enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='cost_splits' and policyname='property_members_cost_splits') then
    execute 'create policy "property_members_cost_splits" on cost_splits using (exists (select 1 from property_members pm where pm.property_id = cost_splits.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- cost_split_shares (may already exist — add property_id if missing)
create table if not exists cost_split_shares (
  id uuid primary key default gen_random_uuid(),
  split_id uuid references cost_splits(id) on delete cascade,
  property_id uuid references properties(id) on delete cascade,
  member_name text not null,
  share_percentage numeric(5,2),
  share_amount numeric(12,2),
  is_paid boolean not null default false,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table cost_split_shares add column if not exists property_id uuid references properties(id) on delete cascade;
alter table cost_split_shares add column if not exists split_id uuid references cost_splits(id) on delete cascade;
alter table cost_split_shares enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='cost_split_shares' and policyname='property_members_cost_split_shares') then
    execute 'create policy "property_members_cost_split_shares" on cost_split_shares using (exists (select 1 from property_members pm where pm.property_id = cost_split_shares.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;
