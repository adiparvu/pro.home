-- ============================================================================
-- G5 FINAL — drop messages.group_id. PREPARED, NOT YET APPLIED.
--
-- GATE (hard): every family device runs the G4 client — the build AFTER
-- 1202. Applying earlier breaks the CURRENT fleet, not just stale devices:
--   - 1202 sub-group sends carry group_id in the INSERT payload
--     (unknown column → every community send errors),
--   - 1202 receipt/reaction/poll loads join messages!inner(group_id),
--   - 1202 community previews select the column.
--
-- Policies are already clean (chat_g5_conversation_scoped_policies removed
-- every policy reference to messages.group_id). REGENERATE the two function
-- bodies below from the LIVE definitions at apply time — P6's standing
-- lesson: the plan is not a snapshot to trust blindly.
-- ============================================================================

-- 1) The stamping trigger loses its group_id resolution path: with the
--    fleet on G4, sub-group writes always carry conversation_id, so the
--    only context-free writers left (Siri intents, any straggler tooling)
--    target the property-wide main chat.
--    Rewrite messages_stamp_conversation: when conversation_id is null and
--    property_id is set, resolve/insert only 'main:<property_id>'.

-- 2) notify_on_group_message: the effective group comes from the
--    conversation alone —
--    v_group := (select c.chat_group_id from conversations c
--                where c.id = new.conversation_id);
--    (drop the coalesce with new.group_id).

-- 3) drop index if exists idx_messages_group;

-- 4) alter table public.messages drop column group_id;

-- 5) Verify after: as a real user, one main-chat send (Siri-shaped, no
--    conversation_id) still lands stamped; one sub-group G4-shaped send
--    notifies members only; advisors clean.
