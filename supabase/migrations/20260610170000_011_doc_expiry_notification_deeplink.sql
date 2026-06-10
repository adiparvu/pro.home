-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 011: Update doc expiry notification action URL
-- ═══════════════════════════════════════════════════════════════════════════
-- Updates action_url from /documents to /documents/{id} for direct deep-link

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
        '/documents/' || v_doc.id::text,
        'document',
        v_doc.id::text,
        '{}'
      );
    end if;
  end loop;
end;
$$ language plpgsql security definer;

grant execute on function public.create_doc_expiry_notifications(uuid) to authenticated;
