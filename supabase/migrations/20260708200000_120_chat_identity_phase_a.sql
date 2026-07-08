-- 120: chat identity migration, phase A (Planul 2) — server groundwork.
--
-- Chat identity today leans on display names in two load-bearing places:
-- chat_blocks (blocker_name/blocked_name + name-based RLS) and the dm_insert
-- block check. Renaming a member silently breaks both. This migration adds
-- the stable-id backbone additively — nothing existing clients send stops
-- working — so the app can move to ids (phase B) and names can become pure
-- display snapshots (phase C).
--
-- It also fixes a latent enforcement hole: dm_insert's block check queried
-- chat_blocks inline, but subqueries inside RLS policies are themselves
-- subject to the referenced table's RLS — and a sender can never see the
-- recipient's block rows, so the NOT EXISTS was always true. The check now
-- goes through a SECURITY DEFINER helper (same pattern as is_property_member).

-- ── 1. chat_blocks: stable-id columns ────────────────────────────────────────

alter table public.chat_blocks
  add column if not exists blocker_id uuid,
  add column if not exists blocked_member_id uuid references public.family_members(id) on delete cascade;

-- Backfill from names (production has zero rows today; kept for completeness).
update public.chat_blocks b
set blocker_id = p.id
from public.profiles p
where b.blocker_id is null
  and coalesce(nullif(p.display_name, ''), nullif(p.full_name, ''), split_part(p.email::text, '@', 1)) = b.blocker_name;

update public.chat_blocks b
set blocked_member_id = fm.id
from public.family_members fm
where b.blocked_member_id is null
  and fm.name = b.blocked_name
  and (b.property_id is null or fm.property_id = b.property_id);

create unique index if not exists chat_blocks_ids_unique
  on public.chat_blocks (blocker_id, blocked_member_id)
  where blocker_id is not null and blocked_member_id is not null;

-- Server-side fill: rows inserted by older clients (names only) become
-- id-complete no matter what the client sends.
create or replace function public.chat_blocks_fill_ids()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.blocker_id is null then
    new.blocker_id := auth.uid();
  end if;
  if new.blocked_member_id is null and new.blocked_name is not null then
    select fm.id into new.blocked_member_id
    from public.family_members fm
    where fm.name = new.blocked_name
      and (new.property_id is null or fm.property_id = new.property_id)
    limit 1;
  end if;
  return new;
end
$$;

drop trigger if exists trg_chat_blocks_fill_ids on public.chat_blocks;
create trigger trg_chat_blocks_fill_ids
  before insert on public.chat_blocks
  for each row execute function public.chat_blocks_fill_ids();

-- Transition RLS: id first, legacy name path kept until phase C. The fill
-- trigger runs before WITH CHECK is evaluated, so old clients pass via the
-- id branch immediately.
drop policy if exists blocks_select on public.chat_blocks;
create policy blocks_select on public.chat_blocks
  for select to authenticated
  using (blocker_id = auth.uid() or blocker_name = current_user_display_name());

drop policy if exists blocks_write on public.chat_blocks;
create policy blocks_write on public.chat_blocks
  for all to authenticated
  using (blocker_id = auth.uid() or blocker_name = current_user_display_name())
  with check (blocker_id = auth.uid() or blocker_name = current_user_display_name());

-- ── 2. Block enforcement that actually fires ────────────────────────────────

create or replace function public.dm_blocked(
  p_sender_id uuid,
  p_sender_name text,
  p_recipient_member_id uuid,
  p_recipient_name text,
  p_property_id uuid
)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select
    -- id-based: the recipient's account blocked any member row of the sender
    exists (
      select 1
      from public.chat_blocks b
      join public.family_members rm on rm.id = p_recipient_member_id
      where b.blocker_id = rm.user_id
        and b.blocked_member_id in (
          select fm.id from public.family_members fm
          where fm.user_id = p_sender_id
            and (p_property_id is null or fm.property_id = p_property_id)
        )
    )
    -- legacy name-based rows, until phase C drops them
    or exists (
      select 1 from public.chat_blocks b
      where b.blocker_name = p_recipient_name
        and b.blocked_name = p_sender_name
    );
$$;

revoke all on function public.dm_blocked(uuid, text, uuid, text, uuid) from public;
grant execute on function public.dm_blocked(uuid, text, uuid, text, uuid) to authenticated;

drop policy if exists dm_insert on public.direct_messages;
create policy dm_insert on public.direct_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and not public.dm_blocked(sender_id, sender_name, recipient_member_id, recipient_name, property_id)
  );

-- ── 3. direct_messages: server-side sender_member_id ────────────────────────
--
-- sender_name is deliberately NOT touched here: clients thread by name until
-- phase B, so normalizing the snapshot now could move bubbles. Phase C does it.

create or replace function public.dm_fill_identity()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.sender_member_id is null and new.property_id is not null then
    select fm.id into new.sender_member_id
    from public.family_members fm
    where fm.user_id = new.sender_id
      and fm.property_id = new.property_id
    limit 1;
  end if;
  return new;
end
$$;

drop trigger if exists trg_dm_fill_identity on public.direct_messages;
create trigger trg_dm_fill_identity
  before insert on public.direct_messages
  for each row execute function public.dm_fill_identity();

update public.direct_messages dm
set sender_member_id = fm.id
from public.family_members fm
where dm.sender_member_id is null
  and dm.property_id is not null
  and fm.property_id = dm.property_id
  and fm.user_id = dm.sender_id;

-- Serves the fill triggers, dm_blocked, and phase-B client lookups.
create index if not exists idx_family_members_user_property
  on public.family_members (user_id, property_id);
