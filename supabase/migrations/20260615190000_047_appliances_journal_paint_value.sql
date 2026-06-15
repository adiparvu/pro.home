-- Appliances
create table public.appliances (
    id uuid primary key default gen_random_uuid(),
    property_id uuid references public.properties(id) on delete cascade not null,
    owner_id uuid references auth.users(id) on delete cascade not null,
    name text not null,
    brand text,
    model_number text,
    serial_number text,
    location text,
    category text not null default 'other',
    purchase_date date,
    warranty_until date,
    purchase_price numeric,
    notes text,
    photo_url text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
alter table public.appliances enable row level security;
create policy "owner_all_appliances" on public.appliances
    for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- Photo Journal
create table public.photo_journal_entries (
    id uuid primary key default gen_random_uuid(),
    property_id uuid references public.properties(id) on delete cascade not null,
    owner_id uuid references auth.users(id) on delete cascade not null,
    zone_id uuid,
    title text not null,
    caption text,
    photo_url text not null,
    taken_at timestamptz not null default now(),
    tags text[],
    created_at timestamptz not null default now()
);
alter table public.photo_journal_entries enable row level security;
create policy "owner_all_photo_journal" on public.photo_journal_entries
    for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- Paint Colors
create table public.paint_colors (
    id uuid primary key default gen_random_uuid(),
    property_id uuid references public.properties(id) on delete cascade not null,
    owner_id uuid references auth.users(id) on delete cascade not null,
    room_name text not null,
    surface text not null default 'walls',
    color_name text not null,
    brand text,
    code text,
    finish text,
    hex_color text,
    notes text,
    created_at timestamptz not null default now()
);
alter table public.paint_colors enable row level security;
create policy "owner_all_paint_colors" on public.paint_colors
    for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- Property Value
create table public.property_value_entries (
    id uuid primary key default gen_random_uuid(),
    property_id uuid references public.properties(id) on delete cascade not null,
    owner_id uuid references auth.users(id) on delete cascade not null,
    value_amount numeric not null,
    currency text not null default 'EUR',
    source text,
    notes text,
    entered_at timestamptz not null default now()
);
alter table public.property_value_entries enable row level security;
create policy "owner_all_property_values" on public.property_value_entries
    for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
