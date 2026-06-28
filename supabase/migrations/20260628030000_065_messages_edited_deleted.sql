-- 065: group messages edit + delete-for-everyone tombstone (parity with DM)
alter table messages
  add column if not exists edited_at timestamptz,
  add column if not exists deleted_for_all boolean not null default false;
