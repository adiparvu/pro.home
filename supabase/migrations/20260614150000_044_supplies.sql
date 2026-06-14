create table public.supply_lists (
    id uuid primary key default gen_random_uuid(),
    property_id uuid references public.properties(id) on delete cascade not null,
    owner_id uuid references auth.users(id) on delete cascade not null,
    name text not null,
    icon text not null default 'cart.fill',
    color text not null default '007AFF',
    note text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.supply_items (
    id uuid primary key default gen_random_uuid(),
    list_id uuid references public.supply_lists(id) on delete cascade not null,
    property_id uuid references public.properties(id) on delete cascade not null,
    name text not null,
    quantity text,
    category text not null default 'other',
    priority text not null default 'medium',
    notes text,
    is_completed boolean not null default false,
    location text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.supply_lists enable row level security;
alter table public.supply_items enable row level security;

create policy "owner_all_lists" on public.supply_lists
    for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "owner_all_items" on public.supply_items
    for all using (
        list_id in (select id from public.supply_lists where owner_id = auth.uid())
    ) with check (
        list_id in (select id from public.supply_lists where owner_id = auth.uid())
    );
