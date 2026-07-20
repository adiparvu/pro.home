-- 142: One device, many signed-in accounts — all of them get push.
--
-- device_tokens was UNIQUE(token): a phone could belong to exactly ONE
-- account, and switching accounts silently stole the token from the previous
-- one, so only the last-active account ever received APNs pushes. The token
-- now binds per (token, user_id): each account signed into the device keeps
-- its own binding, added when that account is (or becomes) active and removed
-- only when that account explicitly signs out. RLS already limits every
-- account to managing its own rows.

alter table public.device_tokens
  drop constraint if exists device_tokens_token_key;

create unique index if not exists device_tokens_token_user_key
  on public.device_tokens (token, user_id);

comment on index public.device_tokens_token_user_key is
  'A device token may be bound to several signed-in accounts at once (multi-account push).';
