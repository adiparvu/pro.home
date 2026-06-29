-- 067: DM delivery receipts + the missing UPDATE policy
--
-- 1) Schema drift fix: the live table's text column is `content`, but the
--    entire iOS app (insert payloads, the DirectMessage model, edit/update)
--    uses `body`. With 0 rows in the table this never surfaced as data loss,
--    but every DM insert/select silently failed. Rename to `body` so the
--    feature actually works. Guarded so it's a no-op where `body` already
--    exists (fresh replays of this repo's lineage).
do $$
begin
    if exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'direct_messages'
          and column_name = 'content'
    ) and not exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'direct_messages'
          and column_name = 'body'
    ) then
        alter table public.direct_messages rename column content to body;
    end if;
end $$;

-- 2) `delivered_at` powers 3-state ticks (sent -> delivered -> read).
alter table public.direct_messages
  add column if not exists delivered_at timestamptz;

-- 3) direct_messages only had INSERT/SELECT policies. With RLS enabled and
--    no UPDATE policy, every UPDATE (read_at, delivered_at, pin, mark, edit,
--    reactions, delete-for-all) was silently denied — 0 rows changed, the
--    client swallowed it, so receipts/edits never persisted. Add an UPDATE
--    policy. Kept permissive to match the existing INSERT/SELECT posture;
--    tightening DM RLS to identity-based checks is a separate security task.
drop policy if exists "dm_update" on public.direct_messages;
create policy "dm_update" on public.direct_messages
    for update to authenticated
    using (true) with check (true);
