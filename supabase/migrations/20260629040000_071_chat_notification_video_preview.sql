-- 071: include video in the group-message notification preview
-- (CREATE OR REPLACE only — same trigger from 069, with a video case added.)

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
    when new.attachment_type = 'video'    then '🎥 Video'
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
