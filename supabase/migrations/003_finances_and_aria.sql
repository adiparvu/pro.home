-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 003: Finances, ARIA Messages, Documents Storage
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Enum Types ─────────────────────────────────────────────────────────────

create type finance_category as enum (
  'maintenance', 'utilities', 'insurance', 'mortgage', 'tax',
  'renovation', 'appliance', 'subscription', 'other'
);

create type finance_type as enum ('expense', 'income', 'budget');

-- ─── Financial Records Table ─────────────────────────────────────────────────

create table public.financial_records (
  id                  uuid primary key default gen_random_uuid(),
  property_id         uuid not null references public.properties(id) on delete cascade,
  title               text not null,
  amount              numeric(14, 2) not null,
  currency            text not null default 'EUR',
  type                finance_type not null default 'expense',
  category            finance_category not null default 'other',
  date                date not null default current_date,
  description         text,
  maintenance_task_id uuid references public.maintenance_tasks(id) on delete set null,
  receipt_url         text,
  tags                text[] not null default '{}',
  created_by          uuid references public.profiles(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table public.financial_records is 'Property financial records — expenses, income, budgets.';

-- ─── ARIA Messages Table ─────────────────────────────────────────────────────

create table public.aria_messages (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  property_id uuid references public.properties(id) on delete cascade,
  role        text not null check (role in ('user', 'assistant')),
  content     text not null,
  created_at  timestamptz not null default now()
);

comment on table public.aria_messages is 'Persisted ARIA conversation messages per user+property.';

-- ─── Indexes ─────────────────────────────────────────────────────────────────

create index idx_financial_records_property on public.financial_records(property_id, date desc);
create index idx_financial_records_type on public.financial_records(property_id, type);
create index idx_aria_messages_user_property on public.aria_messages(user_id, property_id, created_at);

-- ─── Updated-At Triggers ─────────────────────────────────────────────────────

create trigger financial_records_updated_at
  before update on public.financial_records
  for each row execute function public.set_updated_at();

-- ─── Row Level Security ──────────────────────────────────────────────────────

alter table public.financial_records enable row level security;
alter table public.aria_messages enable row level security;

-- Financial records: property-scoped access
create policy "financial_select_member" on public.financial_records for select
  using (public.is_property_member(property_id));
create policy "financial_insert_write" on public.financial_records for insert
  with check (public.has_property_write_access(property_id));
create policy "financial_update_write" on public.financial_records for update
  using (public.has_property_write_access(property_id));
create policy "financial_delete_owner" on public.financial_records for delete
  using (public.is_property_owner_or_partner(property_id));

-- ARIA messages: user owns their own messages
create policy "aria_messages_own" on public.aria_messages for all
  using (user_id = auth.uid());

-- ─── Storage: Documents Bucket ───────────────────────────────────────────────
-- Bucket created via dashboard / MCP: id='documents', public=true, 50MB limit
-- Allowed MIME: pdf, jpeg, png, webp, doc, docx, xls, xlsx

-- Storage RLS policies (applied to storage.objects)
create policy "documents_storage_select" on storage.objects
  for select to authenticated
  using (bucket_id = 'documents');

create policy "documents_storage_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'documents');

create policy "documents_storage_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'documents' and owner = auth.uid());

-- ─── Partition RLS Fix ───────────────────────────────────────────────────────
-- audit_logs partitions need RLS enabled (parent table policies apply, but
-- enabling explicitly ensures direct partition access is also protected)
alter table public.audit_logs_2026 enable row level security;
alter table public.audit_logs_2027 enable row level security;
