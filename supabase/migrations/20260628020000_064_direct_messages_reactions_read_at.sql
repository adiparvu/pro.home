-- 064: DM reactions + read receipts
alter table direct_messages
  add column if not exists reactions jsonb not null default '{}'::jsonb,
  add column if not exists read_at timestamptz;
