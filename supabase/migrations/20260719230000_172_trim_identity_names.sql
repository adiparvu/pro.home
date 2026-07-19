-- 172: Identity-name trim (applied live 2026-07-19).
--
-- The owner's profile display_name became "Adi " (trailing space). The DM
-- pipeline keys conversations by NAME strings, so the history split into
-- "Adi|Bianca" (254 rows) vs "Adi |Bianca" (8 rows) and the open thread
-- rendered a 3-message subset — then EMPTY right after a send (IMG_8679/
-- 8681), while all 263 rows sat intact server-side. Data repaired here;
-- the client moves conversation keying to IDs (chat unification, phased)
-- and trims names at the source.

update public.profiles
   set display_name = trim(display_name), full_name = trim(full_name)
 where display_name != trim(display_name) or full_name != trim(full_name);

update public.direct_messages
   set sender_name = trim(sender_name), recipient_name = trim(recipient_name)
 where sender_name != trim(sender_name) or recipient_name != trim(recipient_name);

update public.family_members
   set name = trim(name) where name != trim(name);

-- Belt: identity-adjacent name columns can never carry edge whitespace
-- again, whatever client writes them.
create or replace function public.trim_dm_names()
returns trigger language plpgsql as $$
begin
  new.sender_name := trim(new.sender_name);
  new.recipient_name := trim(new.recipient_name);
  return new;
end $$;

drop trigger if exists dm_names_trimmed on public.direct_messages;
create trigger dm_names_trimmed
  before insert or update on public.direct_messages
  for each row execute function public.trim_dm_names();

create or replace function public.trim_profile_names()
returns trigger language plpgsql as $$
begin
  new.display_name := trim(new.display_name);
  new.full_name := trim(new.full_name);
  return new;
end $$;

drop trigger if exists profile_names_trimmed on public.profiles;
create trigger profile_names_trimmed
  before insert or update on public.profiles
  for each row execute function public.trim_profile_names();
