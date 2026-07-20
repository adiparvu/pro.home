-- 110: "Send later" — scheduled and recurring chat messages, delivered by
-- pg_cron every minute. Supports one-off sends and daily/weekly/monthly
-- repeats bounded by repeat_until (null = indefinite).

create table if not exists public.scheduled_messages (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  author_id uuid not null,
  author_name text not null,
  target text not null default 'group' check (target in ('group','dm')),
  dm_recipient text,
  body text not null,
  next_send_at timestamptz not null,
  repeat_rule text not null default 'once' check (repeat_rule in ('once','daily','weekly','monthly')),
  repeat_until timestamptz,
  active boolean not null default true,
  last_sent_at timestamptz,
  created_at timestamptz not null default now(),
  constraint dm_needs_recipient check (target <> 'dm' or dm_recipient is not null)
);
create index if not exists scheduled_messages_due_idx
  on public.scheduled_messages (next_send_at) where active;

alter table public.scheduled_messages enable row level security;
drop policy if exists scheduled_messages_own on public.scheduled_messages;
create policy scheduled_messages_own on public.scheduled_messages
  for all
  using (author_id = auth.uid() and public.has_household_access(property_id))
  with check (author_id = auth.uid() and public.has_household_access(property_id));

create or replace function public.process_scheduled_messages()
returns void
language plpgsql security definer
set search_path to 'public'
as $$
declare
  r record;
  step interval;
  next_at timestamptz;
begin
  for r in
    select * from public.scheduled_messages
    where active and next_send_at <= now()
    for update skip locked
  loop
    if r.target = 'group' then
      insert into public.messages (property_id, sender_id, sender_name, body)
      values (r.property_id, r.author_id, r.author_name, r.body);
    else
      insert into public.direct_messages (property_id, sender_id, sender_name, recipient_name, body)
      values (r.property_id, r.author_id, r.author_name, r.dm_recipient, r.body);
    end if;

    if r.repeat_rule = 'once' then
      update public.scheduled_messages
         set active = false, last_sent_at = now()
       where id = r.id;
    else
      step := case r.repeat_rule
                when 'daily' then interval '1 day'
                when 'weekly' then interval '7 days'
                else interval '1 month'
              end;
      next_at := r.next_send_at + step;
      -- After downtime, skip ahead instead of bursting missed sends.
      while next_at <= now() loop
        next_at := next_at + step;
      end loop;
      if r.repeat_until is not null and next_at > r.repeat_until then
        update public.scheduled_messages
           set active = false, last_sent_at = now()
         where id = r.id;
      else
        update public.scheduled_messages
           set next_send_at = next_at, last_sent_at = now()
         where id = r.id;
      end if;
    end if;
  end loop;
end;
$$;

select cron.unschedule(jobid)
from cron.job where jobname = 'process-scheduled-messages';
select cron.schedule('process-scheduled-messages', '* * * * *',
                     $$select public.process_scheduled_messages()$$);
