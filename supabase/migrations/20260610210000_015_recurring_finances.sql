-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 015: Recurring financial records
-- ═══════════════════════════════════════════════════════════════════════════
-- Rent, subscriptions and premiums log themselves: records flagged recurring
-- are cloned on their next_occurrence date by a daily pg_cron job.

alter table public.financial_records
  add column if not exists is_recurring boolean not null default false,
  add column if not exists recurrence_interval text
    check (recurrence_interval in ('monthly', 'yearly')),
  add column if not exists next_occurrence date;

create or replace function public.spawn_recurring_financial_records()
returns integer as $$
declare
  v_rec record;
  v_spawned integer := 0;
begin
  for v_rec in
    select * from public.financial_records
    where is_recurring = true
      and next_occurrence is not null
      and next_occurrence <= current_date
  loop
    -- Clone as a plain (non-recurring) record on the occurrence date
    insert into public.financial_records (
      property_id, title, amount, currency, type, category, date,
      description, tags, created_by, is_recurring
    ) values (
      v_rec.property_id, v_rec.title, v_rec.amount, v_rec.currency,
      v_rec.type, v_rec.category, v_rec.next_occurrence,
      v_rec.description, v_rec.tags, v_rec.created_by, false
    );

    -- Advance the template's next occurrence
    update public.financial_records
    set next_occurrence = case v_rec.recurrence_interval
        when 'yearly' then (v_rec.next_occurrence + interval '1 year')::date
        else (v_rec.next_occurrence + interval '1 month')::date
      end
    where id = v_rec.id;

    v_spawned := v_spawned + 1;
  end loop;

  return v_spawned;
end;
$$ language plpgsql security definer;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'prv-recurring-finances') then
    perform cron.unschedule('prv-recurring-finances');
  end if;
end $$;

select cron.schedule(
  'prv-recurring-finances',
  '30 5 * * *',
  $$select public.spawn_recurring_financial_records()$$
);
