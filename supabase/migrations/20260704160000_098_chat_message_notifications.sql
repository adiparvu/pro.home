-- 098 — chat message notifications
--
-- Every chat message notifies the other active household members (never the
-- sender), so the in-app notification center's "Chat" category is real and
-- the dashboard bell badge lights up on new messages. External cross-app
-- messages (sender_id is null) respect the channel's notify_requests switch.

create or replace function public.notify_chat_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_snippet text;
begin
  -- External gateway messages can be muted per property.
  if new.sender_id is null then
    if exists (
      select 1 from public.cross_app_channels c
      where c.property_id = new.property_id and not c.notify_requests
    ) then
      return new;
    end if;
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
$$;

drop trigger if exists trg_notify_chat_message on public.messages;
create trigger trg_notify_chat_message
  after insert on public.messages
  for each row execute function public.notify_chat_message();
