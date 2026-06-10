-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 014: ARIA weekly digest notification
-- ═══════════════════════════════════════════════════════════════════════════
-- Summarises the week ahead per user (overdue + upcoming tasks, expiring
-- documents, plants needing water, month-to-date spend) as an ARIA
-- notification. Deduplicated to one digest per 6 days. Scheduled Mondays.

create or replace function public.create_weekly_digest_notification(p_user_id uuid)
returns void as $$
declare
  v_property_id uuid;
  v_overdue integer;
  v_upcoming integer;
  v_expiring_docs integer;
  v_thirsty_plants integer;
  v_month_spend numeric;
  v_currency text;
  v_body text;
begin
  -- One digest per 6 days
  if exists (
    select 1 from public.notifications
    where user_id = p_user_id
      and resource_type = 'weekly_digest'
      and created_at > now() - interval '6 days'
  ) then
    return;
  end if;

  -- Most recent active membership property anchors the digest
  select pm.property_id, p.currency into v_property_id, v_currency
  from public.property_members pm
  join public.properties p on p.id = pm.property_id
  where pm.user_id = p_user_id and pm.status = 'active' and p.is_active = true
  order by pm.created_at desc
  limit 1;

  if v_property_id is null then
    return;
  end if;

  select count(*) into v_overdue
  from public.maintenance_tasks
  where property_id = v_property_id and status = 'overdue';

  select count(*) into v_upcoming
  from public.maintenance_tasks
  where property_id = v_property_id
    and status in ('pending', 'in_progress')
    and due_date between current_date and current_date + 7;

  select count(*) into v_expiring_docs
  from public.documents
  where property_id = v_property_id
    and expires_at between now() and now() + interval '30 days';

  select count(*) into v_thirsty_plants
  from public.garden_plants
  where property_id = v_property_id
    and next_watering is not null
    and next_watering <= current_date
    and status not in ('removed', 'harvested');

  select coalesce(sum(amount), 0) into v_month_spend
  from public.financial_records
  where property_id = v_property_id
    and type = 'expense'
    and date >= date_trunc('month', current_date)::date;

  v_body :=
    case when v_overdue > 0
      then v_overdue || ' task' || case when v_overdue <> 1 then 's' else '' end || ' overdue. '
      else '' end ||
    case when v_upcoming > 0
      then v_upcoming || ' task' || case when v_upcoming <> 1 then 's' else '' end || ' due this week. '
      else '' end ||
    case when v_expiring_docs > 0
      then v_expiring_docs || ' document' || case when v_expiring_docs <> 1 then 's' else '' end || ' expiring within 30 days. '
      else '' end ||
    case when v_thirsty_plants > 0
      then v_thirsty_plants || ' plant' || case when v_thirsty_plants <> 1 then 's' else '' end || ' need water. '
      else '' end ||
    'Spent so far this month: ' || coalesce(v_currency, 'EUR') || ' ' || round(v_month_spend) || '.';

  if v_overdue = 0 and v_upcoming = 0 and v_expiring_docs = 0 and v_thirsty_plants = 0 then
    v_body := 'All clear — no overdue tasks, expiring documents or thirsty plants. ' || v_body;
  end if;

  insert into public.notifications (
    property_id, user_id, title, body, priority, status,
    module, action_url, resource_type, resource_id, metadata
  ) values (
    v_property_id, p_user_id,
    'Your week at a glance',
    v_body,
    'normal', 'unread', 'aria', '/', 'weekly_digest', p_user_id, '{}'
  );
end;
$$ language plpgsql security definer;

grant execute on function public.create_weekly_digest_notification(uuid) to authenticated;

-- Weekly schedule: Mondays 07:00 UTC
do $$
begin
  if exists (select 1 from cron.job where jobname = 'prv-weekly-digest') then
    perform cron.unschedule('prv-weekly-digest');
  end if;
end $$;

select cron.schedule(
  'prv-weekly-digest',
  '0 7 * * 1',
  $$
  select public.create_weekly_digest_notification(pm.user_id)
  from (select distinct user_id from public.property_members where status = 'active') pm
  $$
);
