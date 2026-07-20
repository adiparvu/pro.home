-- 130: Per-recipient chat notifications.
--
-- Two defects made chat notifications not properly per-user:
--
--  1. The group `messages` table carried TWO AFTER-INSERT notification
--     triggers — notify_chat_message AND notify_on_group_message — and each
--     inserted a notifications row for every active member. So a single group
--     message produced two identical notifications per recipient. We keep ONE
--     path for normal member messages (notify_on_group_message, which has the
--     richer media previews) and narrow notify_chat_message to ONLY the
--     cross-app / system case (sender_id is null), which the group function
--     doesn't cover — no more duplicates.
--
--  2. Direct-message notifications resolved the recipient by fuzzy NAME
--     (recipient_name = profiles.display_name/full_name). After the chat
--     identity migration (120) the durable target is recipient_member_id →
--     family_members.user_id; name matching could hit the wrong user, miss, or
--     even resolve to the sender. We now target the stable id and never notify
--     the sender of their own message (name matching stays only as a legacy
--     fallback for rows predating the id columns).

-- ── 1. Group: notify_chat_message handles only cross-app/system messages ─────
create or replace function public.notify_chat_message()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_snippet text;
begin
  -- Normal member messages (sender_id present) are handled exclusively by
  -- notify_on_group_message — return early so they aren't notified twice.
  if new.sender_id is not null then
    return new;
  end if;

  -- Cross-app / system message: a channel may opt out of request notifications.
  if exists (
    select 1 from public.cross_app_channels c
    where c.property_id = new.property_id and not c.notify_requests
  ) then
    return new;
  end if;

  v_snippet := left(coalesce(nullif(trim(new.body), ''), '📎'), 140);

  insert into public.notifications
    (property_id, user_id, title, body, priority, module, action_url,
     resource_type, resource_id)
  select new.property_id, m.user_id, coalesce(new.sender_name, 'Chat'),
         v_snippet, 'normal', 'chat', '/chat', 'message', new.id
  from public.property_members m
  where m.property_id = new.property_id
    and m.status = 'active'
    and m.user_id is not null
    and m.user_id is distinct from new.sender_id;

  return new;
end;
$function$;

-- ── 2. DM: target the recipient by stable identity, never the sender ─────────
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

  -- Stable identity first (chat identity migration 120): the recipient member's
  -- linked account. family_members.user_id is null for members without an
  -- account — nobody to notify, correctly.
  if new.recipient_member_id is not null then
    select fm.user_id into v_user
    from public.family_members fm
    where fm.id = new.recipient_member_id
    limit 1;
  end if;

  -- Legacy fallback for DMs that predate recipient_member_id.
  if v_user is null and coalesce(new.recipient_name, '') <> '' then
    select p.id into v_user
    from public.profiles p
    join public.property_members pm
      on pm.user_id = p.id and pm.status = 'active'
    where pm.property_id = new.property_id
      and (p.display_name = new.recipient_name or p.full_name = new.recipient_name)
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
    coalesce(nullif(new.sender_name, ''), 'New message'),
    left(coalesce(new.body, ''), 140), 'normal', 'unread',
    'chat', '/chat', 'direct_message', new.id, '{}'
  );
  return new;
end;
$function$;

-- ── 3. One-time cleanup of the historical duplicates ─────────────────────────
-- Remove the legacy 'message' chat notifications that duplicate a
-- 'group_message' row for the same recipient + message (the double-trigger
-- artefact). Cross-app 'message' rows with no group counterpart are kept.
delete from public.notifications n
where n.resource_type = 'message' and n.module = 'chat'
  and exists (
    select 1 from public.notifications g
    where g.resource_type = 'group_message'
      and g.user_id = n.user_id
      and g.resource_id = n.resource_id
  );
