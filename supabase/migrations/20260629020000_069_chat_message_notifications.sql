-- 069: chat message notifications
--
-- Creates a notifications row on every new chat message so the existing
-- web-push dispatch delivers it (and it shows in the in-app notification
-- center). iOS APNs is layered on top separately (device_tokens + edge
-- function). module = 'chat' so the client can filter these if desired.

-- ─── Group messages ─────────────────────────────────────────────────────────
create or replace function public.notify_on_group_message()
returns trigger as $$
declare
  v_member record;
  v_preview text;
begin
  if coalesce(new.deleted_for_all, false) then return new; end if;

  v_preview := case
    when new.body is not null and new.body <> '' then left(new.body, 140)
    when new.attachment_type = 'image'    then '📷 Photo'
    when new.attachment_type = 'audio'    then '🎤 Voice message'
    when new.attachment_type = 'location' then '📍 Location'
    when new.attachment_type = 'file'     then '📎 File'
    when new.attachment_type = 'sticker'  then '😀 Sticker'
    when new.attachment_type = 'poll'     then '📊 Poll'
    when new.attachment_type = 'event'    then '📅 Event'
    else 'New message'
  end;

  for v_member in
    select user_id from public.property_members
    where property_id = new.property_id
      and status = 'active'
      and user_id is not null
      and user_id <> new.sender_id
  loop
    insert into public.notifications (
      property_id, user_id, title, body, priority, status,
      module, action_url, resource_type, resource_id, metadata
    ) values (
      new.property_id, v_member.user_id,
      coalesce(nullif(new.sender_name, ''), 'New message'),
      v_preview, 'normal', 'unread',
      'chat', '/chat', 'group_message', new.id, '{}'
    );
  end loop;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_notify_on_group_message on public.messages;
create trigger trg_notify_on_group_message
  after insert on public.messages
  for each row execute function public.notify_on_group_message();

-- ─── Direct messages ────────────────────────────────────────────────────────
-- DMs are name-based (no recipient user_id), so map the recipient display
-- name to a profile that is an active member of the property. Best-effort:
-- if no match (e.g. a family member who isn't an app user), skip silently.
create or replace function public.notify_on_direct_message()
returns trigger as $$
declare
  v_user uuid;
begin
  if coalesce(new.deleted_for_all, false) then return new; end if;

  select p.id into v_user
  from public.profiles p
  join public.property_members pm
    on pm.user_id = p.id and pm.status = 'active'
  where pm.property_id = new.property_id
    and (p.display_name = new.recipient_name or p.full_name = new.recipient_name)
  limit 1;

  if v_user is not null then
    insert into public.notifications (
      property_id, user_id, title, body, priority, status,
      module, action_url, resource_type, resource_id, metadata
    ) values (
      new.property_id, v_user,
      coalesce(nullif(new.sender_name, ''), 'New message'),
      left(coalesce(new.body, ''), 140), 'normal', 'unread',
      'chat', '/chat', 'direct_message', new.id, '{}'
    );
  end if;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_notify_on_direct_message on public.direct_messages;
create trigger trg_notify_on_direct_message
  after insert on public.direct_messages
  for each row execute function public.notify_on_direct_message();
