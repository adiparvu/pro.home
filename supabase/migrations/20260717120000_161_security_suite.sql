-- 161: Security suite — the four tables that turn the Security page's
-- promises into real features:
--   • device_sessions          — real per-device session registry ("Sesiuni active")
--   • account_security_events  — server-side ACCOUNT security journal + alerts
--                                (`security_events` already belongs to the
--                                smart-home property module — different domain)
--   • trusted_persons   — trusted people stored on the account, not one phone
--   • backup_codes      — hashed one-time codes verified server-side at the
--                         app-level MFA gate (NOT password recovery — the
--                         client copy must stay honest about that)
-- All four are strictly per-user: nobody reads or writes anyone else's rows.

-- ── Device sessions ─────────────────────────────────────────────────────────
create table if not exists public.device_sessions (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null references auth.users(id) on delete cascade,
    device_id    text not null,           -- identifierForVendor
    device_name  text not null default '',
    model        text not null default '',
    os_version   text not null default '',
    app_build    text not null default '',
    created_at   timestamptz not null default now(),
    last_seen_at timestamptz not null default now(),
    unique (user_id, device_id)
);

create index if not exists device_sessions_user_idx
    on public.device_sessions (user_id, last_seen_at desc);

alter table public.device_sessions enable row level security;

create policy "device_sessions_select_own" on public.device_sessions
    for select using (auth.uid() = user_id);
create policy "device_sessions_insert_own" on public.device_sessions
    for insert with check (auth.uid() = user_id);
create policy "device_sessions_update_own" on public.device_sessions
    for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "device_sessions_delete_own" on public.device_sessions
    for delete using (auth.uid() = user_id);

-- ── Account security events ─────────────────────────────────────────────────
create table if not exists public.account_security_events (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references auth.users(id) on delete cascade,
    type       text not null,             -- new_device_login | password_reset_requested | totp_enabled | totp_disabled | backup_codes_generated | session_revoked
    payload    jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index if not exists account_security_events_user_idx
    on public.account_security_events (user_id, created_at desc);

alter table public.account_security_events enable row level security;

create policy "account_security_events_select_own" on public.account_security_events
    for select using (auth.uid() = user_id);
create policy "account_security_events_insert_own" on public.account_security_events
    for insert with check (auth.uid() = user_id);
create policy "account_security_events_delete_own" on public.account_security_events
    for delete using (auth.uid() = user_id);

-- ── Trusted persons ─────────────────────────────────────────────────────────
create table if not exists public.trusted_persons (
    id                     uuid primary key default gen_random_uuid(),
    user_id                uuid not null references auth.users(id) on delete cascade,
    name                   text not null,
    email                  text not null default '',
    can_emergency_access   boolean not null default false,
    can_approve_recovery   boolean not null default false,
    can_transfer_ownership boolean not null default false,
    created_at             timestamptz not null default now()
);

create index if not exists trusted_persons_user_idx
    on public.trusted_persons (user_id, created_at);

alter table public.trusted_persons enable row level security;

create policy "trusted_persons_select_own" on public.trusted_persons
    for select using (auth.uid() = user_id);
create policy "trusted_persons_insert_own" on public.trusted_persons
    for insert with check (auth.uid() = user_id);
create policy "trusted_persons_update_own" on public.trusted_persons
    for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "trusted_persons_delete_own" on public.trusted_persons
    for delete using (auth.uid() = user_id);

-- ── Backup codes ────────────────────────────────────────────────────────────
-- One row per code, SHA-256 hex hash only. A code is spent by setting
-- used_at; regeneration deletes the user's rows and inserts a fresh set.
create table if not exists public.backup_codes (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references auth.users(id) on delete cascade,
    code_hash  text not null,
    used_at    timestamptz,
    created_at timestamptz not null default now(),
    unique (user_id, code_hash)
);

create index if not exists backup_codes_user_idx
    on public.backup_codes (user_id);

alter table public.backup_codes enable row level security;

create policy "backup_codes_select_own" on public.backup_codes
    for select using (auth.uid() = user_id);
create policy "backup_codes_insert_own" on public.backup_codes
    for insert with check (auth.uid() = user_id);
create policy "backup_codes_update_own" on public.backup_codes
    for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "backup_codes_delete_own" on public.backup_codes
    for delete using (auth.uid() = user_id);
