-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 013: Fix uuid/text mismatch in notification generators
-- ═══════════════════════════════════════════════════════════════════════════
-- notifications.resource_id is uuid; the generators compared/inserted ::text,
-- which made the dedup checks raise "operator does not exist: uuid = text"
-- and the functions fail silently when invoked via PostgREST. Redefine all
-- five generators with native uuid handling.

-- ─── Documents ───────────────────────────────────────────────────────────────
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
      where resource_id = v_doc.id
        and resource_type = 'document'
        and user_id = p_user_id
        and created_at > now() - interval '24 hours'
    ) then
      insert into public.notifications (
        property_id, user_id, title, body, priority, status,
        module, action_url, resource_type, resource_id, metadata
      ) values (
        v_doc.property_id, p_user_id,
        'Expiring: ' || v_doc.name,
        v_doc.name || ' expires in ' || v_days_left || ' day' ||
          case when v_days_left <> 1 then 's' else '' end || '.',
        (case when v_days_left <= 7 then 'high' else 'normal' end)::public.notification_priority,
        'unread', 'documents',
        '/documents/' || v_doc.id,
        'document', v_doc.id, '{}'
      );
    end if;
  end loop;
end;
$$ language plpgsql security definer;

-- ─── Recalls ─────────────────────────────────────────────────────────────────
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
      where resource_id = v_item.id
        and resource_type = 'inventory_item'
        and user_id = p_user_id
        and created_at > now() - interval '24 hours'
    ) then
      insert into public.notifications (
        property_id, user_id, title, body, priority, status,
        module, action_url, resource_type, resource_id, metadata
      ) values (
        v_item.property_id, p_user_id,
        'Safety Recall: ' || v_item.name,
        coalesce(v_item.brand || ' ', '') || v_item.name ||
          ' has an active safety recall. Check manufacturer details.',
        'critical', 'unread', 'inventory',
        '/inventory/' || v_item.id,
        'inventory_item', v_item.id, '{}'
      );
    end if;
  end loop;
end;
$$ language plpgsql security definer;

-- ─── Overdue tasks ───────────────────────────────────────────────────────────
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
      where resource_id = v_task.id
        and resource_type = 'maintenance_task'
        and user_id = p_user_id
        and created_at > now() - interval '24 hours'
    ) then
      insert into public.notifications (
        property_id, user_id, title, body, priority, status,
        module, action_url, resource_type, resource_id, metadata
      ) values (
        v_task.property_id, p_user_id,
        'Overdue: ' || v_task.title,
        'This task was due ' ||
          coalesce(to_char(v_task.due_date, 'Mon DD'), 'recently') ||
          ' and is now overdue.',
        'high', 'unread', 'maintenance',
        '/maintenance/' || v_task.id,
        'maintenance_task', v_task.id, '{}'
      );
    end if;
  end loop;
end;
$$ language plpgsql security definer;

-- ─── Garden watering ─────────────────────────────────────────────────────────
create or replace function public.create_garden_watering_notifications(p_user_id uuid)
returns void as $$
declare
  v_plant record;
begin
  for v_plant in
    select gp.id, gp.name, gp.next_watering, gp.property_id
    from public.garden_plants gp
    join public.property_members pm on pm.property_id = gp.property_id
    where pm.user_id = p_user_id
      and pm.status = 'active'
      and gp.next_watering is not null
      and gp.next_watering <= current_date
      and gp.status not in ('removed', 'harvested')
  loop
    if not exists (
      select 1 from public.notifications
      where resource_id = v_plant.id
        and resource_type = 'garden_plant'
        and user_id = p_user_id
        and created_at > now() - interval '24 hours'
    ) then
      insert into public.notifications (
        property_id, user_id, title, body, priority, status,
        module, action_url, resource_type, resource_id, metadata
      ) values (
        v_plant.property_id, p_user_id,
        'Watering due: ' || v_plant.name,
        v_plant.name || ' was scheduled for watering on ' ||
          to_char(v_plant.next_watering, 'Mon DD') || '.',
        'normal', 'unread', 'garden',
        '/garden/plants/' || v_plant.id,
        'garden_plant', v_plant.id, '{}'
      );
    end if;
  end loop;
end;
$$ language plpgsql security definer;

-- ─── Warranty expiry ─────────────────────────────────────────────────────────
create or replace function public.create_warranty_expiry_notifications(p_user_id uuid)
returns void as $$
declare
  v_item record;
  v_days_left integer;
begin
  for v_item in
    select i.id, i.name, i.brand, i.property_id, i.warranty_expires
    from public.inventory_items i
    join public.property_members pm on pm.property_id = i.property_id
    where pm.user_id = p_user_id
      and pm.status = 'active'
      and i.warranty_expires is not null
      and i.warranty_expires > current_date
      and i.warranty_expires <= current_date + interval '30 days'
  loop
    v_days_left := (v_item.warranty_expires - current_date);

    if not exists (
      select 1 from public.notifications
      where resource_id = v_item.id
        and resource_type = 'inventory_warranty'
        and user_id = p_user_id
        and created_at > now() - interval '24 hours'
    ) then
      insert into public.notifications (
        property_id, user_id, title, body, priority, status,
        module, action_url, resource_type, resource_id, metadata
      ) values (
        v_item.property_id, p_user_id,
        'Warranty expiring: ' || v_item.name,
        coalesce(v_item.brand || ' ', '') || v_item.name ||
          ' warranty expires in ' || v_days_left || ' day' ||
          case when v_days_left <> 1 then 's' else '' end ||
          '. Consider claims or an extension before it lapses.',
        (case when v_days_left <= 7 then 'high' else 'normal' end)::public.notification_priority,
        'unread', 'inventory',
        '/inventory/' || v_item.id,
        'inventory_warranty', v_item.id, '{}'
      );
    end if;
  end loop;
end;
$$ language plpgsql security definer;
