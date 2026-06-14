create table public.plants (
    id uuid primary key default gen_random_uuid(),
    property_id uuid references public.properties(id) on delete cascade not null,
    owner_id uuid references auth.users(id) on delete cascade not null,
    name text not null,
    species text,
    location text,
    last_watered_at timestamptz,
    watering_interval_days int not null default 7,
    health_status text not null default 'good',
    notes text,
    emoji text not null default '🌿',
    photo_url text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.plants enable row level security;

create policy "owner_all_plants" on public.plants
    for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
