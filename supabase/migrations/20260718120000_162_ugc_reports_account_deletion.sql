-- 162: App Store compliance — UGC message reporting + real account deletion.
--
-- (a) content_reports (Guideline 1.2): a signed-in member reports a chat
--     message. WRITE-ONLY from the API: reporters INSERT their own report;
--     no select/update/delete policies exist, so reports are readable only
--     with the service role (the moderation side). The body snapshot is
--     captured at report time so moderation sees what was reported even if
--     the message is later edited or deleted.
--
-- (b) delete_my_account: the RPC the app's Security screen has always
--     called — it existed nowhere (audit blocker: the delete button lied).
--     SECURITY DEFINER so it may delete the auth.users row; every
--     user-keyed table references auth.users(id) with ON DELETE CASCADE /
--     SET NULL (verified across migrations 001..161), so the per-user rows
--     go with it and shared household content survives with authorship
--     nulled. Deleting the auth row also invalidates every session and
--     refresh token for the account.

create table if not exists public.content_reports (
    id            uuid primary key default gen_random_uuid(),
    property_id   uuid,
    message_id    uuid not null,
    message_kind  text not null check (message_kind in ('group', 'dm')),
    reported_by   uuid not null references auth.users(id) on delete cascade,
    reason        text not null check (char_length(reason) <= 200),
    body_snapshot text,
    created_at    timestamptz not null default now()
);

alter table public.content_reports enable row level security;

drop policy if exists content_reports_insert_own on public.content_reports;
create policy content_reports_insert_own
    on public.content_reports
    for insert to authenticated
    with check (reported_by = auth.uid());

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if auth.uid() is null then
        raise exception 'not authenticated';
    end if;
    delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
