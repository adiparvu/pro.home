-- 111: App-wide notification generator.
--
-- The in-app notification bell must cover the whole product, not just chat:
-- tasks due/overdue, documents and warranties about to expire, plants that
-- need water, package deliveries, rent day, expiring invitations and
-- birthdays. A pg_cron job runs every 30 minutes and inserts rows into
-- public.notifications for every active, non-guest member of the property.
--
-- Idempotency: each notification carries a dedup_key; a partial unique index
-- on (user_id, dedup_key) plus ON CONFLICT DO NOTHING guarantees each event
-- notifies a user exactly once (daily events embed the date in the key,
-- monthly events the month, yearly events the year).
--
-- Type notes (learned the hard way):
--   * maintenance_tasks.status is the task_status ENUM  -> compare via ::text
--   * maintenance_tasks.due_date is a DATE              -> compare to current_date
--   * packages.status / live_status are enums           -> coalesce via ::text

alter table public.notifications
  add column if not exists dedup_key text;

create unique index if not exists notifications_dedup_idx
  on public.notifications (user_id, dedup_key)
  where dedup_key is not null;

create or replace function public.generate_app_notifications()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  -- Recipients: every active, non-guest member of each property.
  create temp table if not exists _recipients on commit drop as
    select pm.property_id, pm.user_id
    from public.property_members pm
    where pm.status = 'active' and pm.role <> 'guest';

  -- 1. Tasks due today
  insert into public.notifications (property_id, user_id, title, body, module, resource_type, resource_id, action_url, dedup_key)
  select t.property_id, r.user_id, 'Task scadent azi', t.title, 'tasks', 'task', t.id,
         'prvio://tasks/' || t.id, 'task-due:' || t.id || ':' || current_date
  from public.maintenance_tasks t join _recipients r on r.property_id = t.property_id
  where coalesce(t.status::text,'') <> 'completed'
    and t.due_date = current_date
  on conflict (user_id, dedup_key) where dedup_key is not null do nothing;

  -- 2. Tasks overdue (once per task)
  insert into public.notifications (property_id, user_id, title, body, module, resource_type, resource_id, action_url, dedup_key)
  select t.property_id, r.user_id, 'Task restant', t.title, 'tasks', 'task', t.id,
         'prvio://tasks/' || t.id, 'task-overdue:' || t.id
  from public.maintenance_tasks t join _recipients r on r.property_id = t.property_id
  where coalesce(t.status::text,'') <> 'completed'
    and t.due_date < current_date
  on conflict (user_id, dedup_key) where dedup_key is not null do nothing;

  -- 3. Documents expiring within 30 days
  insert into public.notifications (property_id, user_id, title, body, module, resource_type, resource_id, dedup_key)
  select d.property_id, r.user_id, 'Document care expiră', d.name, 'documents', 'document', d.id,
         'doc-exp:' || d.id
  from public.documents d join _recipients r on r.property_id = d.property_id
  where d.expires_at is not null
    and left(d.expires_at::text, 10)::date between current_date and current_date + 30
  on conflict (user_id, dedup_key) where dedup_key is not null do nothing;

  -- 4. Inventory warranties expiring within 30 days
  insert into public.notifications (property_id, user_id, title, body, module, resource_type, resource_id, dedup_key)
  select i.property_id, r.user_id, 'Garanție care expiră', i.name, 'inventory', 'inventory_item', i.id,
         'warranty:' || i.id
  from public.inventory_items i join _recipients r on r.property_id = i.property_id
  where i.warranty_expires is not null
    and left(i.warranty_expires::text, 10)::date between current_date and current_date + 30
  on conflict (user_id, dedup_key) where dedup_key is not null do nothing;

  -- 5. Plants needing water (daily)
  insert into public.notifications (property_id, user_id, title, body, module, resource_type, resource_id, dedup_key)
  select p.property_id, r.user_id, 'Plantă de udat', p.name, 'plants', 'plant', p.id,
         'plant-water:' || p.id || ':' || current_date
  from public.plants p join _recipients r on r.property_id = p.property_id
  where p.watering_interval_days is not null
    and coalesce(p.last_watered_at, now() - interval '365 days')
        + make_interval(days => p.watering_interval_days) <= now()
  on conflict (user_id, dedup_key) where dedup_key is not null do nothing;

  -- 6a. Packages out for delivery
  insert into public.notifications (property_id, user_id, title, body, module, resource_type, resource_id, dedup_key)
  select k.property_id, r.user_id, 'Colet în livrare azi', k.description, 'deliveries', 'package', k.id,
         'pkg-out:' || k.id
  from public.packages k join _recipients r on r.property_id = k.property_id
  where coalesce(k.live_status::text, k.status::text) in ('out_for_delivery','outfordelivery')
  on conflict (user_id, dedup_key) where dedup_key is not null do nothing;

  -- 6b. Packages delivered
  insert into public.notifications (property_id, user_id, title, body, module, resource_type, resource_id, dedup_key)
  select k.property_id, r.user_id, 'Colet livrat', k.description, 'deliveries', 'package', k.id,
         'pkg-delivered:' || k.id
  from public.packages k join _recipients r on r.property_id = k.property_id
  where coalesce(k.live_status::text, k.status::text) = 'delivered'
  on conflict (user_id, dedup_key) where dedup_key is not null do nothing;

  -- 7. Rent due today (monthly)
  insert into public.notifications (property_id, user_id, title, body, module, resource_type, resource_id, dedup_key)
  select l.property_id, r.user_id, 'Chiria scadentă azi',
         coalesce('Chirie: ' || l.monthly_rent::text, 'Chiria lunară'), 'finances', 'lease', l.id,
         'rent:' || l.id || ':' || to_char(current_date, 'YYYY-MM')
  from public.tenant_leases l join _recipients r on r.property_id = l.property_id
  where l.payment_day = extract(day from current_date)::int
  on conflict (user_id, dedup_key) where dedup_key is not null do nothing;

  -- 8. Invitations expiring within 2 days
  insert into public.notifications (property_id, user_id, title, body, module, resource_type, resource_id, dedup_key)
  select i.property_id, r.user_id, 'Invitație care expiră',
         coalesce(i.name, i.email), 'members', 'invitation', i.id,
         'invite-exp:' || i.id
  from public.member_invitations i join _recipients r on r.property_id = i.property_id
  where i.revoked_at is null
    and i.expires_at between now() and now() + interval '2 days'
  on conflict (user_id, dedup_key) where dedup_key is not null do nothing;

  -- 9. Birthdays today (yearly)
  insert into public.notifications (property_id, user_id, title, body, module, resource_type, resource_id, dedup_key)
  select f.property_id, r.user_id, 'Zi de naștere azi', f.name, 'family', 'family_member', f.id,
         'bday:' || f.id || ':' || extract(year from current_date)::int
  from public.family_members f join _recipients r on r.property_id = f.property_id
  where f.birthday is not null
    and to_char(f.birthday, 'MM-DD') = to_char(current_date, 'MM-DD')
  on conflict (user_id, dedup_key) where dedup_key is not null do nothing;

  drop table if exists _recipients;
end;
$function$;

-- Run every 30 minutes.
select cron.schedule('app-notifications', '*/30 * * * *',
                     'select public.generate_app_notifications()')
where not exists (select 1 from cron.job where jobname = 'app-notifications');
