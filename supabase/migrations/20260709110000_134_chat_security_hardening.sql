-- 134: Chat security hardening (audit lot 1).
-- S1 community isolation (RLS + notifications), S2 delete-for-everyone content
-- blanking, S3 DM recipient content/TTL lockdown, S4 server-stamped sender_name,
-- S5 poll-vote membership, S6 real community admin.

-- ── Helper: is a user a member of a community sub-group? ─────────────────────
-- Community membership is contact-based: chat_group_members.member_id is a
-- FamilyMember.id (uuid as text) for real members, "you" for the creator, or
-- "ext_*" for externals. Map member_id -> family_members.user_id (account), and
-- always treat the group creator as a member. Compared as text to avoid casting
-- the non-uuid "you"/"ext_" tokens.
create or replace function public.is_chat_group_member(p_group_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path to 'public'
as $$
  select p_user_id is not null and (
    exists (select 1 from public.chat_groups g
            where g.id = p_group_id and g.created_by = p_user_id)
    or exists (
      select 1 from public.chat_group_members cgm
      join public.family_members fm on fm.id::text = cgm.member_id
      where cgm.group_id = p_group_id and fm.user_id = p_user_id
    )
  );
$$;

-- ── S1a: messages SELECT is group-scoped for sub-groups ──────────────────────
-- Main property chat (group_id IS NULL) stays member-wide. A sub-group's history
-- is readable only by the sender, the group creator, and linked group members.
drop policy if exists messages_select on public.messages;
create policy messages_select on public.messages
  for select
  using (
    sender_id = auth.uid()
    or (group_id is null and public.is_property_member(property_id))
    or (group_id is not null and public.is_chat_group_member(group_id, auth.uid()))
  );

-- ── S1b: group notifications scoped to the sub-group's members ───────────────
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
      'chat', v_action, 'group_message', new.id, '{}'
    );
  end loop;
  return new;
end;
$function$;

-- ── S4: server-stamp sender_name from the authenticated user's identity ──────
-- Prevents display-name impersonation and closes the legacy name-based block
-- bypass. Only stamps normal client inserts (auth.uid() = sender_id); leaves
-- cron/service inserts (scheduled messages, cross-app) untouched.
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
    select coalesce(nullif(p.display_name, ''), nullif(p.full_name, ''))
      into v_name
    from public.profiles p where p.id = auth.uid();
    if v_name is not null then
      new.sender_name := v_name;
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_stamp_sender_name_messages on public.messages;
create trigger trg_stamp_sender_name_messages
  before insert on public.messages
  for each row execute function public.chat_stamp_sender_name();

drop trigger if exists trg_stamp_sender_name_dm on public.direct_messages;
create trigger trg_stamp_sender_name_dm
  before insert on public.direct_messages
  for each row execute function public.chat_stamp_sender_name();

-- ── S2: "delete for everyone" blanks the content at the DB ──────────────────
create or replace function public.messages_content_guard()
returns trigger
language plpgsql
as $function$
begin
  if new.deleted_for_all and not coalesce(old.deleted_for_all, false) then
    new.body := null;
    new.attachment_url := null;
    new.attachment_type := null;
    new.latitude := null;
    new.longitude := null;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_messages_content_guard on public.messages;
create trigger trg_messages_content_guard
  before update on public.messages
  for each row execute function public.messages_content_guard();

-- ── S2+S3: DM guard — recipient may only touch interaction columns, and
-- "delete for everyone" blanks the body. ────────────────────────────────────
-- When the updater is NOT the sender (recipient acting), content, identity and
-- TTL columns are forced back to their stored values, so a recipient can never
-- rewrite the sender's words or defeat a disappearing timer. read/delivered
-- receipts, reactions, pin and mark remain freely updatable. Service-role
-- updates (auth.uid() null) are trusted and skip the lock.
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

drop trigger if exists trg_dm_content_guard on public.direct_messages;
create trigger trg_dm_content_guard
  before update on public.direct_messages
  for each row execute function public.dm_content_guard();

-- ── S5: poll votes require property membership ──────────────────────────────
drop policy if exists poll_votes_insert_own on public.message_poll_votes;
create policy poll_votes_insert_own on public.message_poll_votes
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and public.is_property_member(property_id)
  );

-- ── S6: real community admin (only the creator manages the group/members) ───
drop policy if exists groups_write on public.chat_groups;
create policy groups_insert on public.chat_groups
  for insert to authenticated
  with check (public.is_property_member(property_id));
create policy groups_modify on public.chat_groups
  for update to authenticated
  using (created_by = auth.uid())
  with check (created_by = auth.uid());
create policy groups_delete on public.chat_groups
  for delete to authenticated
  using (created_by = auth.uid());

drop policy if exists group_members_write on public.chat_group_members;
create policy group_members_write on public.chat_group_members
  for all to authenticated
  using (exists (select 1 from public.chat_groups g
                 where g.id = chat_group_members.group_id and g.created_by = auth.uid()))
  with check (exists (select 1 from public.chat_groups g
                      where g.id = chat_group_members.group_id and g.created_by = auth.uid()));
