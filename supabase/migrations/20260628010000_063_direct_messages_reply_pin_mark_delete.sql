-- 063: bring direct_messages to parity with group messages
-- reply, pin, mark, delete-for-everyone tombstone, edited marker
alter table direct_messages
  add column if not exists reply_to uuid,
  add column if not exists deleted_for_all boolean not null default false,
  add column if not exists edited_at timestamptz,
  add column if not exists pinned boolean not null default false,
  add column if not exists is_marked boolean not null default false;
