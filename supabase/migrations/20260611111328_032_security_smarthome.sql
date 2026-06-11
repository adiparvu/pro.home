-- Migration 032: Security & Smart Home tables
-- smart_home_tokens
create table if not exists smart_home_tokens (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  name text not null,
  token text unique not null,
  is_active boolean not null default true,
  last_used_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table smart_home_tokens enable row level security;
create policy "property_members_smart_home_tokens" on smart_home_tokens
  using (exists (
    select 1 from property_members pm
    where pm.property_id = smart_home_tokens.property_id
      and pm.user_id = (select auth.uid())
      and pm.status = 'active'
  ));

-- smart_home_events
create table if not exists smart_home_events (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  token_id uuid references smart_home_tokens(id) on delete set null,
  event_type text not null,
  device_name text,
  payload jsonb,
  recorded_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
alter table smart_home_events enable row level security;
create policy "property_members_smart_home_events" on smart_home_events
  using (exists (
    select 1 from property_members pm
    where pm.property_id = smart_home_events.property_id
      and pm.user_id = (select auth.uid())
      and pm.status = 'active'
  ));

-- security_schedules (may already exist from earlier migration)
create table if not exists security_schedules (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  name text not null,
  schedule_type text not null default 'routine' check (schedule_type in ('routine', 'inspection', 'patrol', 'alarm_test')),
  frequency text not null default 'weekly' check (frequency in ('daily', 'weekly', 'monthly', 'custom')),
  day_of_week int check (day_of_week between 0 and 6),
  time_of_day time,
  last_completed_at timestamptz,
  next_due_at timestamptz,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table security_schedules enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='security_schedules' and policyname='property_members_security_schedules') then
    execute 'create policy "property_members_security_schedules" on security_schedules using (exists (select 1 from property_members pm where pm.property_id = security_schedules.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- temp_access_codes
create table if not exists temp_access_codes (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  code text not null,
  label text not null,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  max_uses int,
  use_count int not null default 0,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table temp_access_codes enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='temp_access_codes' and policyname='property_members_temp_access_codes') then
    execute 'create policy "property_members_temp_access_codes" on temp_access_codes using (exists (select 1 from property_members pm where pm.property_id = temp_access_codes.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- outbound_webhooks
create table if not exists outbound_webhooks (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  name text not null,
  url text not null,
  secret text,
  events text[] not null default '{}',
  is_active boolean not null default true,
  last_triggered_at timestamptz,
  last_status_code int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table outbound_webhooks enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='outbound_webhooks' and policyname='property_members_outbound_webhooks') then
    execute 'create policy "property_members_outbound_webhooks" on outbound_webhooks using (exists (select 1 from property_members pm where pm.property_id = outbound_webhooks.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;
