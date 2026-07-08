# PRVIO Document Intelligence Center — specification (user vision, 2026-07-08)

Documents grow from a file drawer into the house's intelligence center:
dynamic per-category forms, issuer and identifier records, multi-file
storage with OCR prefill, relations to anything in the house (the fridge's
page shows its warranty, invoice and manual), lifecycle automations,
per-document security, history, financial value feeding expenses, and
linked document chains (contract → invoices → addendum → receipts).

Honesty rules: extraction shows what it actually read (review before save);
AI-assisted steps are gated on verified model capabilities; no security
toggle ships unless it enforces.

## What already exists (build on, don't duplicate)

- `documents` module, private bucket + signed URLs (P0-E), document scanner
  (VisionKit, #112), Vision OCR engine tuned by the receipts work,
  notifications engine (migration 111) + local notifications, EventKit
  calendar/reminders integration (#43, build 878), BiometricAuth + ChatLock
  pattern (Face ID gating), expenses/budgets module, FormKit, GuideSheet.
- iOS Files importer already reaches iCloud Drive, Google Drive and Dropbox
  through their Files providers — "import from anywhere" is one picker, not
  three SDKs.

## Phase D1 — Data model + dynamic per-category form

- Migration: extend `documents` with subcategory, tags (text[]), priority
  (normal/important/critical/urgent), issued_at, expires_at, renew_at,
  notify_at, issuer (company, contact person, phone, email, website,
  client number), identifiers (document number, series, contract code,
  client code, fiscal code, policy number, barcode/QR payload), value +
  currency + vat + recurrence (one-off/monthly/quarterly/yearly).
- Dynamic form on FormKit: base fields always visible; category drives the
  sections that appear (Contract → issuer+identifiers+value+renewal;
  Garanție → purchase date+duration+linked appliance; Asigurare → policy
  number+insurer+renewal; Factură → value+recurrence+issuer…).
- RO+EN, Liquid Glass, Dynamic Type from day one.

## Phase D2 — Files layer + OCR prefill

- New `document_files` (document_id, url, kind: photo/pdf/scan, page_count,
  version, created_at): photos, PDFs, auto-scan (VisionKit) and Files
  import (covers iCloud/GDrive/Dropbox providers) attach MULTIPLE files
  per document.
- OCR prefill: Vision text recognition over the scanned/imported pages +
  deterministic extractors (dates → issued/expiry candidates, amounts →
  value, "nr. contract/serie/polita" patterns → identifiers, known-issuer
  lexicon: Allianz, ENGIE, Electrica, Digi, Orange, Vodafone…) fill the
  form BEFORE the user types; every extracted field is shown for review,
  never silently saved.

## Phase D3 — AI Smart Scan (gated)

- "Am identificat: Contract Orange · expiră 18.06.2028 · client XXXXX" —
  the OCR text goes to ARIA for structured extraction when the backing
  model is verified available; the result prefills the same review UI.
  Without AI the deterministic extractor from D2 remains the story.
  Long-contract summary (duration, obligations, costs, key clauses) rides
  the same gate.

## Phase D4 — Relations everywhere

- New `document_links` (document_id, target_kind: property/room/vehicle/
  person/pet/plant/appliance/element, target_id) + reverse sections on the
  target pages: an appliance's page lists its warranty, invoice, manual,
  energy certificate; a car's page its insurance and ITP.
- `related_documents` (parent/child) chains: contract → invoices →
  addendum → receipts, rendered as a linked list on the document page.

## Phase D5 — Lifecycle: automations, history, versions

- Expiry engine on the existing notification generator: configurable rules
  (30 days before → notify; today → critical notification; warranties →
  30-day reminder; policies → calendar event via EventKit). Defaults per
  category, overridable per document (notify_at).
- `document_events` timeline: created/edited/viewed/shared/downloaded/
  expired/renewed — rendered as History on the document page.
- Versions: replacing a file bumps `document_files.version`, prior
  versions stay listed and openable.
- Financial: value+recurrence feed the expenses dashboard (monthly view
  includes recurring document costs).

## Phase D6 — Security, validation, semantic search

- Per-document security: Face ID/PIN lock (ChatLock pattern), read-only
  flag, hide-from-family (RLS: owner-only visibility) — each toggle backed
  by real enforcement, or it doesn't ship.
- Validation sweeps: duplicates (same identifier/issuer+number), expired,
  incomplete (category-required fields missing) → a review inbox with
  one-tap fixes.
- Search ladder, honest: (1) full-field keyword search incl. OCR text and
  tags; (2) synonym-aware RO/EN matching ("garanția mașinii de spălat" →
  warranty + appliance link); (3) true semantic search via embeddings
  (pgvector) as an explicit later step if approved — infrastructure cost
  named before building.

## Sequencing & estimates

D1 (1–2 builds) → D2 (2) → D4 (1–2) → D5 (2) → D3 (1, gated verification
first) → D6 (2). Each phase green on CI, RO+EN, production-ready.
