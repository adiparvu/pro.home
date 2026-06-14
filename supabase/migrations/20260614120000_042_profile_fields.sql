-- Richer profile: first/last name, birth date, social links, notes
alter table public.profiles
    add column if not exists first_name   text,
    add column if not exists last_name    text,
    add column if not exists birth_date   date,
    add column if not exists social_links jsonb not null default '[]'::jsonb,
    add column if not exists notes        text;
