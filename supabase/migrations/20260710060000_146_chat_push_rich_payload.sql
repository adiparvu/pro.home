-- 146: Chat pushes carry what a rich notification needs.
--
-- The iOS Notification Service Extension renders the sender's avatar
-- (Communication Notifications) and attaches voice/photo media to the
-- expanded notification — both need to ride in the push payload. Stamp the
-- notification metadata with the sender's avatar, the sender id (groups only
-- carried it implicitly) and the message's media path + kind. send-chat-push
-- forwards them (signing private chat-media paths on the way out).
-- Trigger bodies are otherwise identical to migration 144.

-- ── 0. Classify a DM body's media exactly like dm_body_preview does ─────────
create or replace function public.dm_media_kind(p_body text)
returns text
language plpgsql
immutable
set search_path to 'public'
as $function$
declare
  v text := coalesce(p_body, '');
  l text;
begin
  -- Prose contains whitespace; a storage path or URL never does.
  if v = '' or v ~ '[[:space:]]' then return null; end if;
  l := lower(v);
  if l like '%/dm-audio/%' or l like '%.m4a' then return 'audio'; end if;
  if l like '%/dm-video/%' or l like '%.mp4' or l like '%.mov' then return 'video'; end if;
  if (l like '%.jpg' or l like '%.jpeg' or l like '%.png' or l like '%.webp')
     and (l like '%/dm/%' or l like '%/dm-images/%' or l like 'http%') then
    return 'image';
  end if;
  return null;
end;
$function$;

-- ── 1. DM notifications: avatar + media ─────────────────────────────────────
create or replace function public.notify_on_direct_message()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_user uuid;
  v_media_kind text;
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

  v_media_kind := public.dm_media_kind(new.body);

  insert into public.notifications (
    property_id, user_id, title, body, priority, status,
    module, action_url, resource_type, resource_id, metadata
  ) values (
    new.property_id, v_user,
    coalesce(nullif(btrim(new.sender_name), ''), 'New message'),
    public.dm_body_preview(new.body), 'normal', 'unread',
    'chat', '/chat', 'direct_message', new.id,
    jsonb_strip_nulls(jsonb_build_object(
      'kind', 'dm',
      'peer_user_id', new.sender_id,
      'peer_name', btrim(coalesce(new.sender_name, '')),
      'avatar_url', (select p.avatar_url from public.profiles p where p.id = new.sender_id),
      'media_kind', v_media_kind,
      'media_path', case when v_media_kind is not null then new.body else null end
    ))
  );
  return new;
end;
$function$;

-- ── 2. Group notifications: sender id + avatar + media ──────────────────────
create or replace function public.notify_on_group_message()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_member record;
  v_preview text;
  v_action text;
  v_avatar text;
begin
  if coalesce(new.deleted_for_all, false) then return new; end if;

  v_preview := case
    when new.body is not null and new.body <> '' then left(new.body, 140)
    when new.attachment_type = 'image'    then '📷 Photo'
    when new.attachment_type = 'video'    then '🎥 Video'
    when new.attachment_type = 'audio'    then '🎤 Voice message'
    when new.attachment_type = 'location' then '📍 Location'
    when new.attachment_type = 'file'     then '📎 File'
    when new.attachment_type = 'sticker'  then '😀 Sticker'
    when new.attachment_type = 'poll'     then '📊 Poll'
    when new.attachment_type = 'event'    then '📅 Event'
    else 'New message'
  end;

  -- Sub-group messages deep-link to the group and reach only its members.
  v_action := case when new.group_id is not null
                   then '/communities/' || new.group_id::text
                   else '/chat' end;

  select p.avatar_url into v_avatar
  from public.profiles p where p.id = new.sender_id;

  for v_member in
    select user_id from public.property_members
    where property_id = new.property_id
      and status = 'active'
      and user_id is not null
      and user_id <> new.sender_id
      and (new.group_id is null
           or public.is_chat_group_member(new.group_id, user_id))
  loop
    insert into public.notifications (
      property_id, user_id, title, body, priority, status,
      module, action_url, resource_type, resource_id, metadata
    ) values (
      new.property_id, v_member.user_id,
      coalesce(nullif(new.sender_name, ''), 'New message'),
      v_preview, 'normal', 'unread',
      'chat', v_action, 'group_message', new.id,
      jsonb_strip_nulls(jsonb_build_object(
        'kind', case when new.group_id is null then 'chat' else 'community' end,
        'group_id', new.group_id,
        'sender_id', new.sender_id,
        'peer_name', btrim(coalesce(new.sender_name, '')),
        'avatar_url', v_avatar,
        'media_kind', case when new.attachment_type in ('image','audio','video')
                           then new.attachment_type else null end,
        'media_path', case when new.attachment_type in ('image','audio','video')
                           then new.attachment_url else null end
      ))
    );
  end loop;
  return new;
end;
$function$;
