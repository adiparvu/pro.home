-- 072 — Allow any property member to pin / mark a message (WhatsApp-style)
--
-- The single RLS policy on `messages` has WITH CHECK (sender_id = auth.uid()),
-- so a member can only UPDATE their own messages. That makes pinning or marking
-- someone else's message silently fail, and the optimistic UI state then gets
-- wiped on the next reload. Pins (and marks) are group-wide, so expose them via
-- SECURITY DEFINER functions that authorise on property membership instead of
-- authorship, while leaving edit/delete restricted to the sender.

create or replace function public.set_message_pinned(p_message_id uuid, p_pinned boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_property uuid;
begin
  select property_id into v_property from public.messages where id = p_message_id;
  if v_property is null then
    return;
  end if;
  if not public.is_property_member(v_property) then
    raise exception 'not authorised to pin this message';
  end if;
  update public.messages set pinned = p_pinned where id = p_message_id;
end;
$$;

create or replace function public.set_message_marked(p_message_id uuid, p_marked boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_property uuid;
begin
  select property_id into v_property from public.messages where id = p_message_id;
  if v_property is null then
    return;
  end if;
  if not public.is_property_member(v_property) then
    raise exception 'not authorised to mark this message';
  end if;
  update public.messages set is_marked = p_marked where id = p_message_id;
end;
$$;

grant execute on function public.set_message_pinned(uuid, boolean) to authenticated;
grant execute on function public.set_message_marked(uuid, boolean) to authenticated;
