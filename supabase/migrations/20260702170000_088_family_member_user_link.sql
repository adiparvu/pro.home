-- 088 — link chat contacts to auth profiles
--
-- family_members are contacts created by the owner (name/email/colour). When an
-- invited person accepts and gets a profile, we want the contact row to point
-- at their real user so chat/presence can reconcile the two. Nullable — a
-- contact without an account (e.g. a child on chat-only) simply has no link.

alter table public.family_members
  add column if not exists user_id uuid references public.profiles(id) on delete set null;

create index if not exists family_members_user_idx on public.family_members(user_id);
