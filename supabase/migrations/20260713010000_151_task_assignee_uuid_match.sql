-- 151 — fix is_task_assignee: match assignee ids the way the app writes them
--
-- The app stores assignee_ids as UPPERCASE uuid strings (Swift
-- UUID().uuidString), while `fm.id::text` renders lowercase — so the text
-- comparison in migration 090 NEVER matched and a tagged member could not
-- see their own task (the SELECT policy's assignee branch was always
-- false). Migration 149 fixed exactly this case bug in the notification
-- trigger but left the RLS helper untouched: the member got the "you were
-- assigned" push yet the task stayed invisible.
--
-- Also taught here: the `user_<auth-uid>` assignee encoding (149's account
-- fallback for assignees without a linked roster row), which the helper
-- never understood.

create or replace function public.is_task_assignee(p_property_id uuid, p_assignee_ids text[])
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce(
    -- Roster-row assignee: compare as uuid (case-insensitive), only for
    -- entries that actually look like a uuid.
    exists (
      select 1
      from public.family_members fm
      join unnest(p_assignee_ids) x
        on x ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
       and fm.id = x::uuid
      where fm.user_id = auth.uid()
        and fm.property_id = p_property_id
    )
    -- Account-fallback assignee: "user_<auth uid>", case-insensitive.
    or exists (
      select 1
      from unnest(p_assignee_ids) x
      where x ilike 'user\_%' escape '\'
        and substring(x from 6) ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
        and (substring(x from 6))::uuid = auth.uid()
    ),
  false);
$$;

grant execute on function public.is_task_assignee(uuid, text[]) to authenticated;
