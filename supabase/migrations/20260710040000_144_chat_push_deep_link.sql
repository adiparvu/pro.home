-- 144: Tapping a chat push lands in the right conversation.
--
-- The notification rows now carry the conversation identity in `metadata`;
-- send-chat-push forwards it to APNs as a custom `chat` key (plus a
-- per-conversation thread-id so banners stack per thread), and the app's
-- NotificationDelegate routes the tap: a DM opens that peer's thread, group
-- messages open the household chat. Both trigger bodies are otherwise
-- identical to their latest versions (DM: migration 143; group: 134).

-- ── 1. DM notifications carry the peer (the sender, from the recipient's
--       point of view) ────────────────────────────────────────────────────────
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
    public.dm_body_preview(new.body), 'normal', 'unread',
    'chat', '/chat', 'direct_message', new.id,
    jsonb_build_object(
      'kind', 'dm',
      'peer_user_id', new.sender_id,
      'peer_name', btrim(coalesce(new.sender_name, ''))
    )
  );
  return new;
end;
$function$;

-- ── 2. Group notifications carry the conversation scope ─────────────────────
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
      jsonb_build_object(
        'kind', case when new.group_id is null then 'chat' else 'community' end,
        'group_id', new.group_id
      )
    );
  end loop;
  return new;
end;
$function$;
