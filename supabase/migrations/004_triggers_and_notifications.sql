-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 004: Health Score Trigger + Automated Notifications
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Health Score Auto-Recompute ─────────────────────────────────────────────
-- Recomputes property health score whenever a maintenance task's status changes.

create or replace function public.recompute_property_health()
returns trigger as $$
begin
  if old.status is distinct from new.status then
    update public.properties
    set
      health_score = public.compute_health_score(new.property_id),
      health_updated_at = now()
    where id = new.property_id;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_recompute_health_on_task_change
  after update of status on public.maintenance_tasks
  for each row execute function public.recompute_property_health();

-- ─── Overdue Task Notification Trigger ───────────────────────────────────────
-- Creates a notification for every property member when a task becomes overdue.

create or replace function public.notify_on_task_overdue()
returns trigger as $$
declare
  v_member record;
begin
  if new.status = 'overdue' and (old.status is distinct from new.status) then
    for v_member in
      select user_id
      from public.property_members
      where property_id = new.property_id
        and status = 'active'
        and user_id is not null
    loop
      -- Deduplicate: skip if a notification for this task was created in the last 24 h
      if not exists (
        select 1 from public.notifications
        where resource_id = new.id::text
          and resource_type = 'maintenance_task'
          and user_id = v_member.user_id
          and created_at > now() - interval '24 hours'
      ) then
        insert into public.notifications (
          property_id, user_id, title, body, priority, status,
          module, action_url, resource_type, resource_id, metadata
        ) values (
          new.property_id,
          v_member.user_id,
          'Overdue: ' || new.title,
          'This task was due ' ||
            coalesce(to_char(new.due_date, 'Mon DD'), 'recently') ||
            ' and is now overdue.',
          'high',
          'unread',
          'maintenance',
          '/maintenance/' || new.id,
          'maintenance_task',
          new.id::text,
          '{}'
        );
      end if;
    end loop;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_notify_on_task_overdue
  after update of status on public.maintenance_tasks
  for each row execute function public.notify_on_task_overdue();

-- ─── Document Expiry Notification Function ───────────────────────────────────
-- Called on-demand (e.g. from the notifications page) to surface expiring docs.
-- Creates a notification for each document expiring within 30 days.

create or replace function public.create_doc_expiry_notifications(p_user_id uuid)
returns void as $$
declare
  v_doc record;
  v_days_left integer;
begin
  for v_doc in
    select d.id, d.name, d.property_id, d.expires_at
    from public.documents d
    join public.property_members pm on pm.property_id = d.property_id
    where pm.user_id = p_user_id
      and pm.status = 'active'
      and d.expires_at is not null
      and d.expires_at > now()
      and d.expires_at <= now() + interval '30 days'
  loop
    v_days_left := extract(day from v_doc.expires_at - now())::integer;

    if not exists (
      select 1 from public.notifications
      where resource_id = v_doc.id::text
        and resource_type = 'document'
        and user_id = p_user_id
        and created_at > now() - interval '24 hours'
    ) then
      insert into public.notifications (
        property_id, user_id, title, body, priority, status,
        module, action_url, resource_type, resource_id, metadata
      ) values (
        v_doc.property_id,
        p_user_id,
        'Expiring: ' || v_doc.name,
        v_doc.name || ' expires in ' || v_days_left || ' day' ||
          case when v_days_left <> 1 then 's' else '' end || '.',
        case when v_days_left <= 7 then 'high' else 'normal' end,
        'unread',
        'documents',
        '/documents',
        'document',
        v_doc.id::text,
        '{}'
      );
    end if;
  end loop;
end;
$$ language plpgsql security definer;

-- Grant exec to authenticated users (RLS on notifications table enforces ownership)
grant execute on function public.create_doc_expiry_notifications(uuid) to authenticated;
