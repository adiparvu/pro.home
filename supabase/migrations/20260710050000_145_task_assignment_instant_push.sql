-- 145: Being assigned a task buzzes the phone instantly.
--
-- Until now the only task notifications came from the 30-minute generator
-- (migration 111: due today / overdue) — tagging someone on a task made no
-- sound at all. This trigger inserts a notification row for every NEWLY
-- added assignee the moment assignee_ids changes, and the instant-push
-- nudge (migration 118) is broadened to fire for any row stamped
-- metadata.instant = 'true', so the same pg_net → send-chat-push pipeline
-- delivers it to APNs within a second of the save.

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

  -- assignee_ids holds family_members.id strings (migration 090); only
  -- members linked to an account can receive anything. The actor never
  -- notifies themselves (fallback: the task creator, for service writes).
  insert into public.notifications (
    property_id, user_id, title, body, priority, status,
    module, action_url, resource_type, resource_id, metadata
  )
  select new.property_id, fm.user_id,
         'Task nou pentru tine',
         left(coalesce(new.title, ''), 140), 'high', 'unread',
         'tasks', 'prvio://tasks/' || new.id, 'task', new.id,
         jsonb_build_object('instant', 'true', 'task_id', new.id)
  from public.family_members fm
  where fm.id::text = any (v_added)
    and fm.user_id is not null
    and fm.user_id <> coalesce(v_actor, new.created_by)
  group by fm.user_id;

  return new;
end;
$function$;

drop trigger if exists trg_notify_task_assignment on public.maintenance_tasks;
create trigger trg_notify_task_assignment
  after insert or update of assignee_ids on public.maintenance_tasks
  for each row
  execute function public.notify_on_task_assignment();

-- Broaden the instant-push nudge: any notification stamped instant=true
-- (not only chat) pings send-chat-push the moment the row lands. The edge
-- function's claim filter is widened to match.
drop trigger if exists trg_notify_chat_push on public.notifications;
create trigger trg_notify_chat_push
  after insert on public.notifications
  for each row
  when (new.module = 'chat' or (new.metadata ->> 'instant') = 'true')
  execute function public.notify_chat_push();
