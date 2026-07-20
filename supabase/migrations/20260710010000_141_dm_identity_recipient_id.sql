-- 141: Identity-based direct messages (chat-engine unification, phase 1).
--
-- A DM thread's identity is the PEER'S AUTH USER ID; names/avatars are
-- display data hydrated from profiles. Until now the recipient side of a DM
-- was only a family_members row (recipient_member_id) plus a display-name
-- snapshot, and the conversation list derived from the roster BY NAME. A
-- property whose owner has no family_members row (the production case: the
-- roster held everyone *but* the owner) made every DM the owner sent
-- invisible on the recipient's device — no roster entry to attach the thread
-- to. Names are also unreliable ("Adi " with a trailing space; duplicate
-- display names exist).
--
--  1. direct_messages.recipient_id (auth.users) + backfill of both id columns
--     (member-link first, unique trimmed-name match as legacy fallback).
--  2. Covering indexes for both directions of a thread.
--  3. Id-based RLS: the recipient reads/updates their mail by recipient_id,
--     the sender by sender_id (legacy member-based access kept for old rows).
--  4. dm_fill_identity resolves recipient_id <-> recipient_member_id on
--     insert, so rows written by old clients still gain the durable id.
--  5. dm_content_guard freezes recipient_id against recipient tampering.
--  6. chat_stamp_sender_name stores TRIMMED display names.
--  7. notify_on_direct_message targets the recipient by recipient_id first
--     (member link, then trimmed-name match, stay as legacy fallbacks).
--  8. dm_conversation_heads(p_property): one row per peer for the calling
--     user — peer ids, last message, unread count — so the conversation list
--     derives from the MESSAGES, not the roster.

-- ── 1a. The durable recipient identity ───────────────────────────────────────
alter table public.direct_messages
  add column if not exists recipient_id uuid references auth.users (id) on delete set null;

-- ── 1b. Backfill recipient_id from the recipient's linked member row ─────────
update public.direct_messages dm
set recipient_id = fm.user_id
from public.family_members fm
where dm.recipient_id is null
  and dm.recipient_member_id = fm.id
  and fm.user_id is not null;

-- Backfill sender_id from the sender's member row (legacy rows only —
-- dm_insert has required sender_id = auth.uid() since migration 081).
update public.direct_messages dm
set sender_id = fm.user_id
from public.family_members fm
where dm.sender_id is null
  and dm.sender_member_id = fm.id
  and fm.user_id is not null;

-- Legacy fallback: rows whose member link is missing or unlinked resolve by
-- TRIMMED display-name match against the property's active members — but only
-- when the match is unique (duplicate display names must never mis-route).
with candidates as (
  select dm.id as msg_id, min(p.id::text)::uuid as uid, count(distinct p.id) as n
  from public.direct_messages dm
  join public.property_members pm
    on pm.property_id = dm.property_id and pm.status = 'active'
  join public.profiles p on p.id = pm.user_id
  where dm.recipient_id is null
    and dm.property_id is not null
    and btrim(coalesce(dm.recipient_name, '')) <> ''
    and (btrim(coalesce(p.display_name, '')) = btrim(dm.recipient_name)
         or btrim(coalesce(p.full_name, '')) = btrim(dm.recipient_name))
  group by dm.id
)
update public.direct_messages dm
set recipient_id = c.uid
from candidates c
where dm.id = c.msg_id and c.n = 1;

with candidates as (
  select dm.id as msg_id, min(p.id::text)::uuid as uid, count(distinct p.id) as n
  from public.direct_messages dm
  join public.property_members pm
    on pm.property_id = dm.property_id and pm.status = 'active'
  join public.profiles p on p.id = pm.user_id
  where dm.sender_id is null
    and dm.property_id is not null
    and btrim(coalesce(dm.sender_name, '')) <> ''
    and (btrim(coalesce(p.display_name, '')) = btrim(dm.sender_name)
         or btrim(coalesce(p.full_name, '')) = btrim(dm.sender_name))
  group by dm.id
)
update public.direct_messages dm
set sender_id = c.uid
from candidates c
where dm.id = c.msg_id and c.n = 1;

-- ── 2. Covering indexes for both directions of a thread ─────────────────────
create index if not exists direct_messages_property_recipient_created_idx
  on public.direct_messages (property_id, recipient_id, created_at desc);
create index if not exists direct_messages_property_sender_created_idx
  on public.direct_messages (property_id, sender_id, created_at desc);

-- ── 3. Id-based RLS (additive — member-based access keeps old rows working) ──
drop policy if exists dm_select on public.direct_messages;
create policy dm_select on public.direct_messages
  for select to authenticated
  using (
    sender_id = (select auth.uid())
    or recipient_id = (select auth.uid())
    or public.is_my_family_member(recipient_member_id)
  );

-- The recipient may update interaction columns (read_at/delivered_at/
-- reactions/pin/mark) — dm_content_guard (below) freezes everything else.
drop policy if exists dm_update on public.direct_messages;
create policy dm_update on public.direct_messages
  for update to authenticated
  using (
    sender_id = (select auth.uid())
    or recipient_id = (select auth.uid())
    or public.is_my_family_member(recipient_member_id)
  )
  with check (
    sender_id = (select auth.uid())
    or recipient_id = (select auth.uid())
    or public.is_my_family_member(recipient_member_id)
  );

-- ── 4. Fill both recipient identity columns on insert ───────────────────────
-- Old clients send only recipient_member_id; new clients always send
-- recipient_id. Either way the row ends up carrying both when resolvable.
create or replace function public.dm_fill_identity()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.sender_member_id is null and new.property_id is not null then
    select fm.id into new.sender_member_id
    from public.family_members fm
    where fm.user_id = new.sender_id
      and fm.property_id = new.property_id
    limit 1;
  end if;
  if new.recipient_id is null and new.recipient_member_id is not null then
    select fm.user_id into new.recipient_id
    from public.family_members fm
    where fm.id = new.recipient_member_id
    limit 1;
  end if;
  if new.recipient_member_id is null and new.recipient_id is not null
     and new.property_id is not null then
    select fm.id into new.recipient_member_id
    from public.family_members fm
    where fm.user_id = new.recipient_id
      and fm.property_id = new.property_id
    limit 1;
  end if;
  return new;
end
$function$;

-- ── 5. Content guard also freezes recipient_id for non-sender updaters ──────
-- (same body as migration 134 plus the recipient_id line — a recipient could
-- otherwise re-route a thread by rewriting its identity).
create or replace function public.dm_content_guard()
returns trigger
language plpgsql
as $function$
begin
  if auth.uid() is not null and auth.uid() <> old.sender_id then
    new.body                := old.body;
    new.sender_name         := old.sender_name;
    new.sender_id           := old.sender_id;
    new.sender_member_id    := old.sender_member_id;
    new.recipient_name      := old.recipient_name;
    new.recipient_id        := old.recipient_id;
    new.recipient_member_id := old.recipient_member_id;
    new.property_id         := old.property_id;
    new.expires_at          := old.expires_at;
    new.edited_at           := old.edited_at;
    new.reply_to            := old.reply_to;
    new.created_at          := old.created_at;
    new.deleted_for_all     := old.deleted_for_all;
  end if;

  if new.deleted_for_all and not coalesce(old.deleted_for_all, false) then
    new.body := null;
  end if;
  return new;
end;
$function$;

-- ── 6. Server-stamped sender_name is TRIMMED ─────────────────────────────────
-- The production owner profile literally carries "Adi " (trailing space);
-- names are display data and must never encode invisible whitespace.
create or replace function public.chat_stamp_sender_name()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_name text;
begin
  if new.sender_id is not null and new.sender_id = auth.uid() then
    select coalesce(nullif(btrim(p.display_name), ''), nullif(btrim(p.full_name), ''))
      into v_name
    from public.profiles p where p.id = auth.uid();
    if v_name is not null then
      new.sender_name := v_name;
    end if;
  end if;
  return new;
end;
$function$;

-- ── 7. DM notifications target recipient_id first ────────────────────────────
create or replace function public.notify_on_direct_message()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_user uuid;
begin
  if coalesce(new.deleted_for_all, false) then return new; end if;

  -- Durable identity (migration 141): the recipient's auth user id.
  v_user := new.recipient_id;

  -- Legacy fallback 1: the recipient member's linked account (migration 120).
  if v_user is null and new.recipient_member_id is not null then
    select fm.user_id into v_user
    from public.family_members fm
    where fm.id = new.recipient_member_id
    limit 1;
  end if;

  -- Legacy fallback 2: trimmed-name match for rows predating the id columns.
  if v_user is null and btrim(coalesce(new.recipient_name, '')) <> '' then
    select p.id into v_user
    from public.profiles p
    join public.property_members pm
      on pm.user_id = p.id and pm.status = 'active'
    where pm.property_id = new.property_id
      and (btrim(coalesce(p.display_name, '')) = btrim(new.recipient_name)
           or btrim(coalesce(p.full_name, '')) = btrim(new.recipient_name))
    limit 1;
  end if;

  -- No resolvable recipient, or it resolved to the sender → never self-notify.
  if v_user is null or v_user = new.sender_id then
    return new;
  end if;

  insert into public.notifications (
    property_id, user_id, title, body, priority, status,
    module, action_url, resource_type, resource_id, metadata
  ) values (
    new.property_id, v_user,
    coalesce(nullif(btrim(new.sender_name), ''), 'New message'),
    left(coalesce(new.body, ''), 140), 'normal', 'unread',
    'chat', '/chat', 'direct_message', new.id, '{}'
  );
  return new;
end;
$function$;

-- ── 8. Conversation heads: the list derives from MESSAGES, not the roster ───
-- One row per peer for the calling user: the peer's ids/name snapshot, the
-- newest message, and the unread count (inbound rows addressed to auth.uid()
-- with no read receipt). SECURITY INVOKER — RLS decides row visibility.
-- Rows group by the strongest available peer identity: auth user id, then
-- family_members id (contacts without accounts), then the trimmed name
-- (rows predating every id column).
create or replace function public.dm_conversation_heads(p_property uuid)
returns table (
  peer_user_id uuid,
  peer_member_id uuid,
  peer_name text,
  last_message_id uuid,
  last_body text,
  last_sender_id uuid,
  last_created_at timestamptz,
  last_deleted_for_all boolean,
  unread_count bigint
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with visible as (
    select
      dm.id, dm.body, dm.sender_id, dm.recipient_id, dm.created_at,
      dm.read_at, dm.deleted_for_all,
      case when dm.sender_id = auth.uid()
           then coalesce(dm.recipient_id, rfm.user_id)
           else dm.sender_id
      end as peer_uid,
      case when dm.sender_id = auth.uid()
           then dm.recipient_member_id
           else dm.sender_member_id
      end as peer_mid,
      case when dm.sender_id = auth.uid()
           then dm.recipient_name
           else dm.sender_name
      end as peer_nm
    from public.direct_messages dm
    left join public.family_members rfm on rfm.id = dm.recipient_member_id
    where dm.property_id = p_property
  ),
  keyed as (
    select v.*,
      coalesce(v.peer_uid::text, v.peer_mid::text,
               nullif(lower(btrim(coalesce(v.peer_nm, ''))), '')) as peer_key
    from visible v
  ),
  hydrated as (
    select k.*,
      (array_remove(array_agg(k.peer_uid) over w, null))[1] as agg_uid,
      (array_remove(array_agg(k.peer_mid) over w, null))[1] as agg_mid,
      count(*) filter (
        where k.recipient_id = auth.uid()
          and k.read_at is null
          and not coalesce(k.deleted_for_all, false)
          and k.sender_id is distinct from auth.uid()
      ) over w as agg_unread
    from keyed k
    where k.peer_key is not null
    window w as (partition by k.peer_key)
  )
  select distinct on (h.peer_key)
    h.agg_uid,
    h.agg_mid,
    btrim(coalesce(h.peer_nm, '')),
    h.id,
    h.body,
    h.sender_id,
    h.created_at,
    coalesce(h.deleted_for_all, false),
    h.agg_unread
  from hydrated h
  order by h.peer_key, h.created_at desc;
$$;

revoke execute on function public.dm_conversation_heads(uuid) from public, anon;
grant execute on function public.dm_conversation_heads(uuid) to authenticated;
