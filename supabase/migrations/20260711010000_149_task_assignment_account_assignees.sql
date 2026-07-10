-- 149: Task assignment pushes reach every real person.
--
-- Two failures fixed in notify_on_task_assignment (migration 145):
-- 1. The app writes assignee_ids as UPPERCASE uuid strings (Swift
--    UUID().uuidString); comparing them to fm.id::text (lowercase) never
--    matched, so no assignment notification was ever inserted. Compare as
--    uuid, which is case-insensitive.
-- 2. The assignee picker now also stores 'user_<auth uuid>' for account
--    holders without a roster row (the owner on a partner's device);
--    resolve those directly.

create or replace function public.notify_on_task_assignment()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_added text[];
  v_actor uuid := auth.uid();
begin
  -- Only assignees ADDED by this write: someone already on the task must not
  -- be re-notified because an unrelated edit rewrote the array.
  if tg_op = 'UPDATE' then
    select coalesce(array_agg(x), '{}') into v_added
    from unnest(coalesce(new.assignee_ids, '{}')) x
    where x <> all (coalesce(old.assignee_ids, '{}'));
  else
    v_added := coalesce(new.assignee_ids, '{}');
  end if;

  if array_length(v_added, 1) is null then
    return new;
  end if;

  -- Resolve each added entry to an auth user id: bare uuids through the
  -- roster (family_members.id, migration 090), 'user_<uuid>' entries
  -- directly. Free-text ('custom_<name>') entries match neither branch and
  -- stay silent. The actor never notifies themselves (fallback: the task
  -- creator, for service writes).
  insert into public.notifications (
    property_id, user_id, title, body, priority, status,
    module, action_url, resource_type, resource_id, metadata
  )
  select new.property_id, u.uid,
         'Task nou pentru tine',
         left(coalesce(new.title, ''), 140), 'high', 'unread',
         'tasks', 'prvio://tasks/' || new.id, 'task', new.id,
         jsonb_build_object('instant', 'true', 'task_id', new.id)
  from (
    select fm.user_id as uid
    from public.family_members fm
    join unnest(v_added) x
      on x ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
     and fm.id = x::uuid
    where fm.user_id is not null
    union
    select (substring(x from 6))::uuid
    from unnest(v_added) x
    where x ilike 'user\_%' escape '\'
      and substring(x from 6) ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
  ) u
  where u.uid <> coalesce(v_actor, new.created_by)
  group by u.uid;

  return new;
end;
$function$;
