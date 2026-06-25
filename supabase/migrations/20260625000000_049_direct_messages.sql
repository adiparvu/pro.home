-- 049: direct_messages table for 1-on-1 private messaging between family members

create table if not exists public.direct_messages (
    id          uuid         primary key default gen_random_uuid(),
    sender_name text         not null,
    recipient_name text      not null,
    body        text         not null,
    property_id uuid         references public.properties(id) on delete cascade,
    created_at  timestamptz  not null default now()
);

create index if not exists idx_dm_property_created
    on public.direct_messages(property_id, created_at desc);

create index if not exists idx_dm_sender
    on public.direct_messages(sender_name, recipient_name);

alter table public.direct_messages enable row level security;

create policy "dm_insert" on public.direct_messages
    for insert to authenticated with check (true);

create policy "dm_select" on public.direct_messages
    for select to authenticated using (true);

alter publication supabase_realtime add table public.direct_messages;
