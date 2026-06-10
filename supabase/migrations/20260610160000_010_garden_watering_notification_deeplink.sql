-- ═══════════════════════════════════════════════════════════════════════════
-- PRV HOUSE — Migration 010: Update garden watering notification action URL
-- ═══════════════════════════════════════════════════════════════════════════
-- Updates action_url from /garden to /garden/plants/{id} for direct deep-link

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
      where resource_id = v_plant.id::text
        and resource_type = 'garden_plant'
        and user_id = p_user_id
        and created_at > now() - interval '24 hours'
    ) then
      insert into public.notifications (
        property_id, user_id, title, body, priority, status,
        module, action_url, resource_type, resource_id, metadata
      ) values (
        v_plant.property_id,
        p_user_id,
        'Watering due: ' || v_plant.name,
        v_plant.name || ' was scheduled for watering on ' ||
          to_char(v_plant.next_watering, 'Mon DD') || '.',
        'normal',
        'unread',
        'garden',
        '/garden/plants/' || v_plant.id::text,
        'garden_plant',
        v_plant.id::text,
        '{}'
      );
    end if;
  end loop;
end;
$$ language plpgsql security definer;

grant execute on function public.create_garden_watering_notifications(uuid) to authenticated;
