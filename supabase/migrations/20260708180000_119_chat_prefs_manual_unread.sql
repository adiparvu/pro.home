-- 119: manual "mark as unread" flag on conversation prefs.
--
-- The conversations list lets a user mark a thread unread by hand (the blue
-- dot without new messages). Until now that flag lived only in UserDefaults,
-- so it silently diverged between devices while pin/mute/archive synced.
-- One boolean on the existing per-user, per-conversation prefs row fixes it —
-- same RLS, same conflict key, no new table.

alter table public.chat_user_prefs
  add column if not exists manual_unread boolean not null default false;
