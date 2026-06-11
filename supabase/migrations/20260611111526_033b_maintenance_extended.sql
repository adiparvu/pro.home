-- Migration 033b: Maintenance Extended tables
-- defect_logs
create table if not exists defect_logs (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  title text not null,
  description text,
  location text,
  severity text not null default 'medium' check (severity in ('low', 'medium', 'high', 'critical')),
  status text not null default 'open' check (status in ('open', 'in_progress', 'resolved', 'closed', 'wont_fix')),
  reported_by text,
  reported_at timestamptz not null default now(),
  resolved_at timestamptz,
  photo_paths text[] not null default '{}',
  estimated_cost numeric(12,2),
  actual_cost numeric(12,2),
  currency text not null default 'RON',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table defect_logs enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='defect_logs' and policyname='property_members_defect_logs') then
    execute 'create policy "property_members_defect_logs" on defect_logs using (exists (select 1 from property_members pm where pm.property_id = defect_logs.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- seasonal_task_templates
create table if not exists seasonal_task_templates (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  title text not null,
  description text,
  season text not null check (season in ('spring', 'summer', 'autumn', 'winter', 'all')),
  category text,
  estimated_duration_hours numeric(5,2),
  estimated_cost numeric(12,2),
  currency text not null default 'RON',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table seasonal_task_templates enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='seasonal_task_templates' and policyname='property_members_seasonal_task_templates') then
    execute 'create policy "property_members_seasonal_task_templates" on seasonal_task_templates using (exists (select 1 from property_members pm where pm.property_id = seasonal_task_templates.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- recurring_task_templates
create table if not exists recurring_task_templates (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  title text not null,
  description text,
  frequency text not null check (frequency in ('daily', 'weekly', 'monthly', 'quarterly', 'annual')),
  category text,
  estimated_duration_hours numeric(5,2),
  estimated_cost numeric(12,2),
  currency text not null default 'RON',
  last_generated_at timestamptz,
  next_due_at date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table recurring_task_templates enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='recurring_task_templates' and policyname='property_members_recurring_task_templates') then
    execute 'create policy "property_members_recurring_task_templates" on recurring_task_templates using (exists (select 1 from property_members pm where pm.property_id = recurring_task_templates.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- move_checklists
create table if not exists move_checklists (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  type text not null default 'move_in' check (type in ('move_in', 'move_out')),
  tenant_name text,
  scheduled_date date,
  completed_at timestamptz,
  status text not null default 'pending' check (status in ('pending', 'in_progress', 'completed')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table move_checklists enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='move_checklists' and policyname='property_members_move_checklists') then
    execute 'create policy "property_members_move_checklists" on move_checklists using (exists (select 1 from property_members pm where pm.property_id = move_checklists.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;

-- move_checklist_items (may already exist without property_id)
create table if not exists move_checklist_items (
  id uuid primary key default gen_random_uuid(),
  checklist_id uuid references move_checklists(id) on delete cascade,
  property_id uuid references properties(id) on delete cascade,
  title text not null,
  description text,
  category text,
  is_completed boolean not null default false,
  completed_at timestamptz,
  notes text,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table move_checklist_items add column if not exists property_id uuid references properties(id) on delete cascade;
alter table move_checklist_items add column if not exists checklist_id uuid references move_checklists(id) on delete cascade;
alter table move_checklist_items enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='move_checklist_items' and policyname='property_members_move_checklist_items') then
    execute 'create policy "property_members_move_checklist_items" on move_checklist_items using (exists (select 1 from property_members pm where pm.property_id = move_checklist_items.property_id and pm.user_id = (select auth.uid()) and pm.status = ''active''))';
  end if;
end $$;
