-- 121: Document Intelligence Center, phase D1 — the rich document record.
--
-- Documents grow from name + file + category into a full record the dynamic
-- per-category form fills. Everything here is additive and nullable, so
-- existing rows and older clients keep working unchanged; the form only
-- surfaces the fields a given category needs.

alter table public.documents
  -- Classification
  add column if not exists subcategory text,
  add column if not exists priority text not null default 'normal',   -- normal/important/critical/urgent
  -- Key dates (expires_at already exists as a date)
  add column if not exists issued_at date,
  add column if not exists renew_at date,
  add column if not exists notify_at date,
  -- Issuer
  add column if not exists issuer_company text,
  add column if not exists issuer_contact text,
  add column if not exists issuer_phone text,
  add column if not exists issuer_email text,
  add column if not exists issuer_website text,
  add column if not exists client_number text,
  -- Identifiers
  add column if not exists doc_number text,
  add column if not exists series text,
  add column if not exists contract_code text,
  add column if not exists client_code text,
  add column if not exists fiscal_code text,
  add column if not exists policy_number text,
  add column if not exists barcode text,
  -- Financial
  add column if not exists value numeric,
  add column if not exists currency text,
  add column if not exists vat numeric,
  add column if not exists recurrence text;                            -- one-off/monthly/quarterly/yearly

-- Keep the legacy is_critical flag in step with the richer priority so
-- existing badges/queries (isExpiringSoon lists, dashboards) keep working
-- without a rewrite: critical & urgent are the "critical" tier.
update public.documents
set priority = case when is_critical then 'critical' else 'normal' end
where priority = 'normal' and is_critical = true;

-- The expiry sweep and search touch these constantly.
create index if not exists idx_documents_expires_at on public.documents (expires_at)
  where expires_at is not null;
create index if not exists idx_documents_priority on public.documents (property_id, priority);
