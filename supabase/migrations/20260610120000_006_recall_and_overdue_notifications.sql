-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 006: Recall & Overdue On-Demand Notification Functions
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Recall Notifications ────────────────────────────────────────────────────
-- Called on-demand to surface active safety recalls as notifications.
-- Deduplicates within a 24-hour window per item per user.

create or replace function public.create_recall_notifications(p_user_id uuid)
returns void as $$
declare
  v_item record;
begin
  for v_item in
    select i.id, i.name, i.brand, i.property_id
    from public.inventory_items i
    join public.property_members pm on pm.property_id = i.property_id
    where pm.user_id = p_user_id
      and pm.status = 'active'
      and i.recall_active = true
  loop
    if not exists (
      select 1 from public.notifications
      where resource_id = v_item.id::text
        and resource_type = 'inventory_item'
        and user_id = p_user_id
        and created_at > now() - interval '24 hours'
    ) then
      insert into public.notifications (
        property_id, user_id, title, body, priority, status,
        module, action_url, resource_type, resource_id, metadata
      ) values (
        v_item.property_id,
        p_user_id,
        'Safety Recall: ' || v_item.name,
        coalesce(v_item.brand || ' ', '') || v_item.name ||
          ' has an active safety recall. Check manufacturer details.',
        'critical',
        'unread',
        'inventory',
        '/inventory/' || v_item.id,
        'inventory_item',
        v_item.id::text,
        '{}'
      );
    end if;
  end loop;
end;
$$ language plpgsql security definer;

grant execute on function public.create_recall_notifications(uuid) to authenticated;

-- ─── Overdue Task Backfill Notifications ─────────────────────────────────────
-- Surfaces notifications for tasks that are already overdue (missed trigger).
-- Deduplicates within a 24-hour window per task per user.

create or replace function public.create_overdue_task_notifications(p_user_id uuid)
returns void as $$
declare
  v_task record;
begin
  for v_task in
    select mt.id, mt.title, mt.due_date, mt.property_id
    from public.maintenance_tasks mt
    join public.property_members pm on pm.property_id = mt.property_id
    where pm.user_id = p_user_id
      and pm.status = 'active'
      and mt.status = 'overdue'
  loop
    if not exists (
      select 1 from public.notifications
      where resource_id = v_task.id::text
        and resource_type = 'maintenance_task'
        and user_id = p_user_id
        and created_at > now() - interval '24 hours'
    ) then
      insert into public.notifications (
        property_id, user_id, title, body, priority, status,
        module, action_url, resource_type, resource_id, metadata
      ) values (
        v_task.property_id,
        p_user_id,
        'Overdue: ' || v_task.title,
        'This task was due ' ||
          coalesce(to_char(v_task.due_date, 'Mon DD'), 'recently') ||
          ' and is now overdue.',
        'high',
        'unread',
        'maintenance',
        '/maintenance/' || v_task.id,
        'maintenance_task',
        v_task.id::text,
        '{}'
      );
    end if;
  end loop;
end;
$$ language plpgsql security definer;

grant execute on function public.create_overdue_task_notifications(uuid) to authenticated;
