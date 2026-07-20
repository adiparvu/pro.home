-- 127: Document Intelligence, phase D5 (part 1) — history timeline + expiry
-- automations.
--
-- Two additive pieces:
--
--   1. document_events — an append-only activity log per document
--      (created / edited / viewed / shared / downloaded / expired / renewed /
--      file_added / file_removed), rendered as "History" on the document page.
--      Purely additive; nothing else reads it, so older clients are unaffected.
--
--   2. The app-wide notification generator (migration 111,
--      public.generate_app_notifications) gains three document rules that the
--      existing coverage does NOT provide:
--        (a) per-document notify_at override  — fire a reminder once today
--            reaches the user-chosen date;
--        (b) priority-driven criticality      — critical/urgent (or the legacy
--            is_critical flag) documents get a CRITICAL-priority escalation as
--            expiry closes in;
--        (c) renew_at reminders               — 30 days before a renewal date.
--
--      Existing document-expiry coverage is deliberately left untouched:
--        • 111 §3 already emits a plain "expiring within 30 days" heads-up on
--          expires_at (dedup_key 'doc-exp:<id>');
--        • migration 011 (create_doc_expiry_notifications) emits a per-user,
--          days-left countdown for the same 30-day window.
--      So the generic 30-day / today expires_at rule is already handled — this
--      migration layers ONLY notify_at, renew_at and the critical escalation on
--      top, each with its own dedup_key so re-runs never double-notify.

-- ─── 1. Document events timeline ─────────────────────────────────────────────

create table if not exists public.document_events (
  id          uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents(id) on delete cascade,
  kind        text not null,           -- created/edited/viewed/shared/downloaded/
                                        -- expired/renewed/file_added/file_removed
  actor_id    uuid,                     -- auth.uid() of who did it (nullable: system/cron)
  details     jsonb,                    -- small, flat context ({"name": "...", ...})
  at          timestamptz not null default now()
);

create index if not exists idx_document_events_document
  on public.document_events (document_id, at desc);

alter table public.document_events enable row level security;

-- Visibility inherits the parent document exactly like document_files (migration
-- 123): the subquery over public.documents runs with that table's RLS applied,
-- so an event row is reachable precisely when its parent document is — property
-- members and members the document was explicitly shared with, nothing else.
drop policy if exists document_events_access on public.document_events;
create policy document_events_access on public.document_events
  for all to authenticated
  using (exists (select 1 from public.documents d where d.id = document_id))
  with check (exists (select 1 from public.documents d where d.id = document_id));

-- ─── 2. Expiry engine — extend the app-wide notification generator ───────────
--
-- create-or-replace preserving the exact signature (returns void, no args) and
-- every existing rule (§1–§9) verbatim; §10–§12 are the only additions. The
-- pg_cron schedule from 111 already calls this function, so no cron change is
-- needed.

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

  -- ── D5 additions (documents lifecycle) ────────────────────────────────────

  -- 10. Per-document notify_at override (Document Intelligence D1/D5).
  --     When today reaches the user-chosen reminder date, fire once. The
  --     dedup_key embeds notify_at so it never repeats; the 30-day window keeps
  --     a legacy/past notify_at from surfacing an ancient reminder on backfill.
  --     Criticality tracks the document's own priority.
  insert into public.notifications (property_id, user_id, title, body, priority, module, resource_type, resource_id, dedup_key)
  select d.property_id, r.user_id, 'Reminder document', d.name,
         (case when d.priority in ('critical','urgent') or d.is_critical then 'critical' else 'normal' end)::public.notification_priority,
         'documents', 'document', d.id,
         'doc-notify:' || d.id || ':' || d.notify_at
  from public.documents d join _recipients r on r.property_id = d.property_id
  where d.notify_at is not null
    and current_date between d.notify_at and d.notify_at + 30
  on conflict (user_id, dedup_key) where dedup_key is not null do nothing;

  -- 11. Priority-driven criticality: critical/urgent (or legacy is_critical)
  --     documents get a CRITICAL-priority escalation as expiry closes in
  --     (within 7 days). This is an escalation distinct from §3's plain 30-day
  --     heads-up — its own dedup_key (embedding the expiry date) fires once per
  --     expiry, so §3 and §11 never collapse into or duplicate one another.
  insert into public.notifications (property_id, user_id, title, body, priority, module, resource_type, resource_id, dedup_key)
  select d.property_id, r.user_id, 'Document critic expiră', d.name,
         'critical'::public.notification_priority,
         'documents', 'document', d.id,
         'doc-exp-critical:' || d.id || ':' || left(d.expires_at::text, 10)
  from public.documents d join _recipients r on r.property_id = d.property_id
  where d.expires_at is not null
    and (d.priority in ('critical','urgent') or d.is_critical)
    and left(d.expires_at::text, 10)::date between current_date and current_date + 7
  on conflict (user_id, dedup_key) where dedup_key is not null do nothing;

  -- 12. Renewal reminders: 30 days before renew_at. Independent of expires_at
  --     (a document can renew without expiring). dedup_key embeds renew_at so
  --     each renewal cycle notifies once.
  insert into public.notifications (property_id, user_id, title, body, priority, module, resource_type, resource_id, dedup_key)
  select d.property_id, r.user_id, 'Document de reînnoit', d.name,
         (case when d.priority in ('critical','urgent') or d.is_critical then 'high' else 'normal' end)::public.notification_priority,
         'documents', 'document', d.id,
         'doc-renew:' || d.id || ':' || d.renew_at
  from public.documents d join _recipients r on r.property_id = d.property_id
  where d.renew_at is not null
    and current_date between d.renew_at - 30 and d.renew_at
  on conflict (user_id, dedup_key) where dedup_key is not null do nothing;

  drop table if exists _recipients;
end;
$function$;
