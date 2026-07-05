-- 106 — let household members read each other's basic profile
--
-- profiles was readable only by its owner (profiles_select_own), so the app
-- could never show another member's avatar or display name — chat avatars
-- stayed initials even for members with photos, and a members-with-accounts
-- list was impossible. Members of the same property (active) may now read
-- each other's profile rows.

drop policy if exists profiles_select_household on public.profiles;
create policy profiles_select_household on public.profiles
  for select using (
    exists (
      select 1
      from public.property_members me
      join public.property_members them
        on them.property_id = me.property_id
      where me.user_id = auth.uid()
        and me.status = 'active'
        and them.user_id = profiles.id
        and them.status = 'active'
    )
  );
