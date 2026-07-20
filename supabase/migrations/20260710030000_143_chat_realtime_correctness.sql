-- 143: Chat realtime correctness (chat-engine unification, phase 2).
--
--  1. DM push previews: migration 130/141 set the DM notification body to
--     left(body, 140) — but DMs carry media as bare storage paths and rich
--     attachments as marker-encoded JSON in the body, so a photo pushed as
--     "3F2A…/dm/9c1e….jpg" and an event as raw JSON. dm_body_preview() maps
--     every structured DM body to the same human labels the group trigger
--     (migration 134, v_preview) already uses; plain text keeps the 140-char
--     snippet.
--
--  2. Presence hygiene: presence is keyed by (property_id, user_id) — correct —
--     but the user_name display column stored untrimmed profile names ("Adi "
--     with a trailing space in production), which broke every name-keyed
--     legacy lookup. The client now keys presence by user id and trims names;
--     trim the rows already stored so the legacy name fallback can match.

-- ── 1a. Classify a DM body exactly like the client (ChatMedia.dmBodyKind,
--        DMRich markers, SharedContactPayload.dmMarker). ─────────────────────
create or replace function public.dm_body_preview(p_body text)
returns text
language plpgsql
immutable
set search_path to 'public'
as $function$
declare
  v_body  text := coalesce(p_body, '');
  v_lower text;
begin
  if v_body = '' then
    return '';
  end if;

  -- Marker-encoded rich bodies (sentinels no ordinary message starts with).
  if v_body like '📇[%' then return '👤 Contact';  end if;  -- contact card JSON
  if v_body like '📍#%' then return '📍 Location'; end if;  -- "📍#lat,lon"
  if v_body like '🗓️%' then return '📅 Event';    end if;  -- event JSON
  if v_body like '📄#%' then return '📎 File';     end if;  -- file JSON
  if v_body like '🎟️%' then return '😀 Sticker';  end if;  -- sticker id

  -- Media rides as a bare storage path (private bucket) or a legacy public
  -- URL; prose contains whitespace, a path never does.
  if v_body !~ '[[:space:]]' then
    v_lower := lower(v_body);
    if v_lower like '%/dm-audio/%' or v_lower like '%.m4a' then
      return '🎤 Voice message';
    end if;
    if v_lower like '%/dm-video/%' or v_lower like '%.mp4' or v_lower like '%.mov' then
      return '🎥 Video';
    end if;
    if (v_lower like '%.jpg' or v_lower like '%.jpeg'
        or v_lower like '%.png' or v_lower like '%.webp')
       and (v_lower like '%/dm/%' or v_lower like '%/dm-images/%'
            or v_lower like 'http%') then
      return '📷 Photo';
    end if;
  end if;

  return left(v_body, 140);
end;
$function$;

-- ── 1b. DM notifications use the mapped preview ──────────────────────────────
-- Same body as migration 141 §7; only the notification body changes.
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
    'chat', '/chat', 'direct_message', new.id, '{}'
  );
  return new;
end;
$function$;

-- ── 2. Presence display names are TRIMMED (identity stays user_id) ──────────
update public.presence
set user_name = btrim(user_name)
where user_name is distinct from btrim(user_name);
