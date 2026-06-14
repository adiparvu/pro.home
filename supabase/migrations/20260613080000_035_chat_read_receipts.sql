-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 035: Chat Read Receipts (WhatsApp-style)
-- Tracks which household member has seen each chat message, and when.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.message_reads (
  id          uuid primary key default gen_random_uuid(),
  message_id  uuid not null references public.messages(id) on delete cascade,
  property_id uuid references public.properties(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  reader_name text not null default '',
  read_at     timestamptz not null default now()
);

-- One read row per (message, user).
create unique index if not exists uq_message_reads_message_user
  on public.message_reads(message_id, user_id);

create index if not exists idx_message_reads_message  on public.message_reads(message_id);
create index if not exists idx_message_reads_property on public.message_reads(property_id);

alter table public.message_reads enable row level security;

-- Members of the property can see and record read receipts.
do $$ begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'message_reads' and policyname = 'property_members_message_reads_select'
  ) then
    execute 'create policy "property_members_message_reads_select" on public.message_reads
      for select using (exists (
        select 1 from property_members pm
        where pm.property_id = message_reads.property_id
          and pm.user_id = (select auth.uid())
          and pm.status = ''active''
      ))';
  end if;

  if not exists (
    select 1 from pg_policies
    where tablename = 'message_reads' and policyname = 'message_reads_insert_own'
  ) then
    execute 'create policy "message_reads_insert_own" on public.message_reads
      for insert with check (user_id = (select auth.uid()))';
  end if;

  if not exists (
    select 1 from pg_policies
    where tablename = 'message_reads' and policyname = 'message_reads_update_own'
  ) then
    execute 'create policy "message_reads_update_own" on public.message_reads
      for update using (user_id = (select auth.uid()))';
  end if;
end $$;

-- Realtime: broadcast read events so senders see "seen" live.
do $$ begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'message_reads'
  ) then
    execute 'alter publication supabase_realtime add table public.message_reads';
  end if;
exception when others then
  null;
end $$;
