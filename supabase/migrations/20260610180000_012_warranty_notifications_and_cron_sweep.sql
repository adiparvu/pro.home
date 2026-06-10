-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 012: Warranty expiry notifications + scheduled sweep
-- ═══════════════════════════════════════════════════════════════════════════
-- 1. create_warranty_expiry_notifications: inventory items whose warranty
--    expires within 30 days (resource_type 'inventory_warranty' so dedup
--    does not collide with recall notifications on the same item).
-- 2. run_notification_sweep: calls every on-demand generator for every
--    active member, so notifications no longer depend on page loads.
-- 3. pg_cron: daily sweep at 06:00 UTC.

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
      where resource_id = v_item.id::text
        and resource_type = 'inventory_warranty'
        and user_id = p_user_id
        and created_at > now() - interval '24 hours'
    ) then
      insert into public.notifications (
        property_id, user_id, title, body, priority, status,
        module, action_url, resource_type, resource_id, metadata
      ) values (
        v_item.property_id,
        p_user_id,
        'Warranty expiring: ' || v_item.name,
        coalesce(v_item.brand || ' ', '') || v_item.name ||
          ' warranty expires in ' || v_days_left || ' day' ||
          case when v_days_left <> 1 then 's' else '' end ||
          '. Consider claims or an extension before it lapses.',
        case when v_days_left <= 7 then 'high' else 'normal' end,
        'unread',
        'inventory',
        '/inventory/' || v_item.id,
        'inventory_warranty',
        v_item.id::text,
        '{}'
      );
    end if;
  end loop;
end;
$$ language plpgsql security definer;

grant execute on function public.create_warranty_expiry_notifications(uuid) to authenticated;

-- ─── Sweep: run all generators for all active members ───────────────────────

create or replace function public.run_notification_sweep()
returns integer as $$
declare
  v_user record;
  v_count integer := 0;
begin
  for v_user in
    select distinct pm.user_id, pm.property_id
    from public.property_members pm
    where pm.status = 'active'
  loop
    -- Mark overdue tasks first so overdue notifications pick them up
    perform public.mark_overdue_tasks(v_user.property_id);
  end loop;

  for v_user in
    select distinct pm.user_id
    from public.property_members pm
    where pm.status = 'active'
  loop
    perform public.create_doc_expiry_notifications(v_user.user_id);
    perform public.create_recall_notifications(v_user.user_id);
    perform public.create_overdue_task_notifications(v_user.user_id);
    perform public.create_garden_watering_notifications(v_user.user_id);
    perform public.create_warranty_expiry_notifications(v_user.user_id);
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$ language plpgsql security definer;

-- ─── Schedule: daily at 06:00 UTC ────────────────────────────────────────────

create extension if not exists pg_cron;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'prv-notification-sweep') then
    perform cron.unschedule('prv-notification-sweep');
  end if;
end $$;

select cron.schedule(
  'prv-notification-sweep',
  '0 6 * * *',
  $$select public.run_notification_sweep()$$
);
