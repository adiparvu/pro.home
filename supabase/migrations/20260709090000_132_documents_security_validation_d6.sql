-- 132: Document Vault D6 — per-document security, validation support, honest search.
--
-- Adds the server-side backing for the three per-document security controls,
-- persists OCR text so keyword search can honestly include it, and records the
-- document's creator so the "hide from family" ownership check is reliable.
--
-- Everything here is additive and nullable / defaulted, so existing rows
-- (migrations 002 → 131) and older clients keep decoding and working
-- unchanged: read_only and hidden_from_family default false, ocr_text is null.
--
-- Assumes the documents table + its RLS from 002, the family/sharing helpers
-- has_family_access (091) and is_shared_with_me (094), and the D1 rich record
-- (121). The SELECT policy rebuilt here supersedes the one last defined in 094.

-- ── New columns ──────────────────────────────────────────────────────────────
alter table public.documents
  -- Read-only: when true, the client disables every edit affordance and the
  -- guard trigger below rejects any content UPDATE at the database.
  add column if not exists read_only boolean not null default false,
  -- Hide from family: when true, only the creator may SELECT the row (below).
  add column if not exists hidden_from_family boolean not null default false,
  -- Recognized text from scans/photos, captured at add time. Lets keyword
  -- search (D6 tier 1) honestly include OCR content, not just typed fields.
  add column if not exists ocr_text text;

-- Capture the creator on every future insert so "hide from family" always has
-- a reliable owner to scope to. The client also sends uploaded_by explicitly
-- (belt-and-suspenders). Pre-existing rows keep their current uploaded_by
-- (possibly null): such a row can't be hidden by anyone but also isn't hidden
-- from anyone, which is the safe, non-destructive fallback.
alter table public.documents
  alter column uploaded_by set default auth.uid();

comment on column public.documents.read_only is
  'D6: read-only lock. While true, the documents_readonly_guard trigger rejects content edits; flipping the security flags themselves is always allowed.';
comment on column public.documents.hidden_from_family is
  'D6: owner-only visibility. While true, only uploaded_by = auth.uid() may SELECT the row (enforced by documents_select_member RLS).';
comment on column public.documents.ocr_text is
  'D6: recognized text captured at add time, so keyword search can include scanned content.';

-- ── Hide-from-family: owner-only visibility (RLS, database-enforced) ──────────
-- A document keeps its normal family + per-row-shared visibility UNLESS
-- hidden_from_family is set, in which case ONLY its creator can see it. A
-- shared_member_ids grant does NOT override the hide — hiding is strict,
-- owner-only, and enforced here at the database, never merely in the client.
drop policy if exists documents_select_member on public.documents;
create policy documents_select_member on public.documents
  for select using (
    (
      public.has_family_access(property_id)
      or public.is_shared_with_me(property_id, shared_member_ids)
    )
    and (
      not hidden_from_family
      or uploaded_by = auth.uid()
    )
  );

-- ── Read-only: server-side write guard ───────────────────────────────────────
-- The client disables every edit affordance on a read-only document; this
-- trigger is the matching hard guarantee. While a row is read-only, any UPDATE
-- that changes a CONTENT column is rejected — but flipping the security flags
-- themselves (read_only / hidden_from_family) and the housekeeping updated_at
-- stamp is always permitted, so the owner can always lift the lock or change
-- visibility. Diffing to_jsonb minus those keys means any content column added
-- by a future migration is covered automatically, with no edit needed here.
create or replace function public.documents_readonly_guard()
returns trigger
language plpgsql
as $$
begin
  if OLD.read_only then
    if (to_jsonb(NEW) - 'read_only' - 'hidden_from_family' - 'updated_at')
       is distinct from
       (to_jsonb(OLD) - 'read_only' - 'hidden_from_family' - 'updated_at') then
      raise exception
        'document % is read-only; lift the read-only lock before editing', OLD.id
        using errcode = 'check_violation';
    end if;
  end if;
  return NEW;
end;
$$;

-- Fires before set_updated_at (002's "documents_updated_at"): trigger order is
-- alphabetical, and "documents_readonly_guard" < "documents_updated_at". The
-- diff excludes updated_at regardless, so ordering is not load-bearing.
drop trigger if exists documents_readonly_guard on public.documents;
create trigger documents_readonly_guard
  before update on public.documents
  for each row execute function public.documents_readonly_guard();

-- Search over OCR text stays client-side for the loaded working set (≤ 500
-- rows), so no full-text index is required for D6. A GIN index on
-- to_tsvector(ocr_text) is the natural first step ONLY if/when search moves
-- server-side alongside the pgvector tier (tier 3), which is out of scope here.
