-- 125: Document Intelligence, phase D4 — relations everywhere.
--
-- Two kinds of relation:
--  1. document_links — a document is attached to a thing in the house
--     (appliance, room, plant, person, property…). The target's page can then
--     show its own papers: the fridge lists its warranty + invoice + manual.
--  2. related_documents — documents chain to each other (contract → invoices →
--     addendum → receipts), rendered as a linked list on the document page.
--
-- Both inherit visibility from the documents they reference: the subquery over
-- public.documents runs with that table's RLS for the current user, so a link
-- is reachable exactly when its document(s) are. Additive and safe.

-- ── 1. Links to house objects ────────────────────────────────────────────────
create table if not exists public.document_links (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents(id) on delete cascade,
  target_kind text not null,          -- property/room/vehicle/person/pet/plant/appliance/element
  target_id uuid not null,
  created_at timestamptz not null default now(),
  unique (document_id, target_kind, target_id)
);

create index if not exists idx_document_links_document on public.document_links (document_id);
-- The reverse lookup a target page runs: "which documents point at me?"
create index if not exists idx_document_links_target on public.document_links (target_kind, target_id);

alter table public.document_links enable row level security;

drop policy if exists document_links_access on public.document_links;
create policy document_links_access on public.document_links
  for all to authenticated
  using (exists (select 1 from public.documents d where d.id = document_id))
  with check (exists (select 1 from public.documents d where d.id = document_id));

-- ── 2. Document-to-document chains ───────────────────────────────────────────
create table if not exists public.related_documents (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null references public.documents(id) on delete cascade,
  child_id uuid not null references public.documents(id) on delete cascade,
  relation text,                      -- optional: invoice/addendum/receipt/annex…
  created_at timestamptz not null default now(),
  unique (parent_id, child_id),
  check (parent_id <> child_id)
);

create index if not exists idx_related_documents_parent on public.related_documents (parent_id);
create index if not exists idx_related_documents_child on public.related_documents (child_id);

alter table public.related_documents enable row level security;

-- Both ends must be visible to the user — you can't chain to a document you
-- can't see, and you can't see a chain whose other end is hidden from you.
drop policy if exists related_documents_access on public.related_documents;
create policy related_documents_access on public.related_documents
  for all to authenticated
  using (exists (select 1 from public.documents d where d.id = parent_id)
     and exists (select 1 from public.documents d where d.id = child_id))
  with check (exists (select 1 from public.documents d where d.id = parent_id)
          and exists (select 1 from public.documents d where d.id = child_id));
