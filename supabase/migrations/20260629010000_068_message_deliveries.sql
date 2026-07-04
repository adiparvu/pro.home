-- 068: group-chat delivery receipts
--
-- Mirrors message_reads so the group chat can show 3-state ticks
-- (sent -> delivered -> read). A row means a member's device fetched the
-- message. Read state continues to come from message_reads.

create table if not exists public.message_deliveries (
    id             uuid        primary key default gen_random_uuid(),
    message_id     uuid        not null references public.messages(id) on delete cascade,
    property_id    uuid        not null,
    user_id        uuid,
    deliverer_name text        not null,
    delivered_at   timestamptz not null default now(),
    unique (message_id, user_id)
);

create index if not exists idx_message_deliveries_message
    on public.message_deliveries(message_id);
create index if not exists idx_message_deliveries_property
    on public.message_deliveries(property_id);

alter table public.message_deliveries enable row level security;

-- INSERT: a member may only record their own delivery (mirrors message_reads).
drop policy if exists "message_deliveries_insert_own" on public.message_deliveries;
create policy "message_deliveries_insert_own" on public.message_deliveries
    for insert to authenticated
    with check (user_id = (select auth.uid()));

-- SELECT: active members of the property can see delivery receipts.
drop policy if exists "property_members_message_deliveries_select" on public.message_deliveries;
create policy "property_members_message_deliveries_select" on public.message_deliveries
    for select to authenticated
    using (
        exists (
            select 1 from public.property_members pm
            where pm.property_id = message_deliveries.property_id
              and pm.user_id = (select auth.uid())
              and pm.status = 'active'::member_status
        )
    );

alter publication supabase_realtime add table public.message_deliveries;
