-- 135: pin search_path on chat helper functions (audit F7 hardening nit).
-- A mutable search_path on a SECURITY DEFINER-adjacent function is a known
-- Postgres foot-gun; pin it to public for the chat disappearing-message helper.
do $$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.proname='touch_chat_disappear') then
    alter function public.touch_chat_disappear() set search_path = 'public';
  end if;
end $$;
