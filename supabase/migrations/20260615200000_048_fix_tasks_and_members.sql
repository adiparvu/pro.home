-- Migration 048: Fix maintenance_tasks schema + auto-add property owner to property_members

-- ─── 1. Add missing assignee columns to maintenance_tasks ────────────────────
alter table public.maintenance_tasks
    add column if not exists assignee_ids   text[] not null default '{}',
    add column if not exists assignee_names text[] not null default '{}';

-- ─── 2. Auto-add property creator to property_members as 'owner' ─────────────
-- When a property is inserted, the authenticated user becomes owner.

create or replace function public.handle_new_property()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
    insert into public.property_members (property_id, user_id, role, status)
    values (new.id, auth.uid(), 'owner', 'active')
    on conflict (property_id, user_id) do update
        set role   = excluded.role,
            status = excluded.status;
    return new;
end;
$$;

drop trigger if exists on_property_created on public.properties;
create trigger on_property_created
    after insert on public.properties
    for each row execute function public.handle_new_property();

-- ─── 3. Repair existing data ──────────────────────────────────────────────────
-- For any property that has zero members, we cannot determine the owner
-- retroactively without a creator column. Add creator_id so future creates track it.
alter table public.properties
    add column if not exists creator_id uuid references auth.users(id) on delete set null;

-- ─── 4. Fix notifications RLS if missing ──────────────────────────────────────
do $$
begin
    if not exists (
        select 1 from pg_policies
        where tablename = 'notifications'
          and policyname = 'notifications_select_own'
    ) then
        execute $pol$
            create policy "notifications_select_own"
                on public.notifications for select
                using (user_id = auth.uid())
        $pol$;
    end if;

    if not exists (
        select 1 from pg_policies
        where tablename = 'notifications'
          and policyname = 'notifications_update_own'
    ) then
        execute $pol$
            create policy "notifications_update_own"
                on public.notifications for update
                using (user_id = auth.uid())
                with check (user_id = auth.uid())
        $pol$;
    end if;
end;
$$;
