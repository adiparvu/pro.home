-- 073 — sync group description + member labels across devices
--
-- Previously the group description (GroupDescriptionStore) and per-member labels
-- (MemberLabelStore) lived only in UserDefaults on one device. These two tables
-- back them so they sync for every property member. member_id is text so it can
-- hold both a member UUID and the literal "you" used for the current user.

create table if not exists public.chat_group_settings (
  property_id uuid primary key references public.properties(id) on delete cascade,
  description text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.chat_member_labels (
  property_id uuid not null references public.properties(id) on delete cascade,
  member_id text not null,
  label text not null default '',
  updated_at timestamptz not null default now(),
  primary key (property_id, member_id)
);

alter table public.chat_group_settings enable row level security;
alter table public.chat_member_labels enable row level security;

drop policy if exists members_rw on public.chat_group_settings;
create policy members_rw on public.chat_group_settings
  for all
  using (public.is_property_member(property_id))
  with check (public.is_property_member(property_id));

drop policy if exists members_rw on public.chat_member_labels;
create policy members_rw on public.chat_member_labels
  for all
  using (public.is_property_member(property_id))
  with check (public.is_property_member(property_id));
