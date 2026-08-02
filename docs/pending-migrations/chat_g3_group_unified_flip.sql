-- ============================================================================
-- G3 — groups flip onto conversations. PREPARED, NOT YET APPLIED.
--
-- PRECONDITION: every family device runs the G2 client (dual-read behind
-- chat_rollout.group_unified_read). Flipping earlier blinds old clients:
-- they filter group reads on `conversation_id IS NULL`, and this migration
-- stamps that column on every group row.
--
-- REGENERATE the two notification-function bodies from the LIVE definitions
-- at apply time (P6's standing lesson) — the shapes below are the plan, not
-- a snapshot to trust blindly.
-- ============================================================================

-- 1) A conversation exists for every scope that ever spoke.
insert into public.conversations (kind, group_key, property_id)
select distinct 'group', 'main:' || m.property_id, m.property_id
from public.messages m
where m.conversation_id is null and m.group_id is null
on conflict (group_key) where group_key is not null do nothing;

insert into public.conversations (kind, group_key, property_id, chat_group_id)
select distinct 'group', 'grp:' || m.group_id, m.property_id, m.group_id
from public.messages m
where m.conversation_id is null and m.group_id is not null
on conflict (group_key) where group_key is not null do nothing;

-- 2) Backfill history.
update public.messages m
set conversation_id = c.id
from public.conversations c
where m.conversation_id is null
  and c.kind = 'group'
  and c.group_key = coalesce('grp:' || m.group_id::text, 'main:' || m.property_id::text);

-- 3) Stamp every future legacy write server-side (stragglers,
--    ChatGroupService, scheduled sends): BEFORE INSERT, when
--    conversation_id is null, resolve it from (property, group).
--    (Function body: select/insert the conversation exactly like
--    group_open_conversation but definer-internal, no auth gate — the
--    INSERT policy already authorized the writer.)

-- 4) The two group-notification triggers currently fire
--    WHEN (conversation_id IS NULL) — after stamping, that is NEVER.
--    Recreate them to fire on every insert and early-return inside the
--    function when the row's conversation is dm-kind. notify_on_dm_message
--    is already kind-aware (G2 did it).

-- 5) The search RPC the G2 client already calls (falls back until then):
--    group_search_has_match(p_property uuid, p_query text) returns boolean
--    security invoker: exists(select 1 from messages m join conversations c
--    on c.id = m.conversation_id where c.kind='group' and
--    c.property_id = p_property and m.body ilike p_query-escaped limit 1).

-- 6) The flip, last:
-- update public.chat_rollout set group_unified_read = true;
