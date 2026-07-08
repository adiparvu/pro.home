-- 123: Document Intelligence, phase D2 — multi-file layer.
--
-- A document is no longer one file. A contract can carry the signed scan,
-- the PDF the issuer emailed, and a photo of the last page; a warranty its
-- receipt and the product manual. These attachments live in document_files
-- and reuse the existing private `documents` bucket. The primary file stays
-- on documents.file_url (unchanged), so pre-D2 rows and older clients keep
-- working — this table is purely additive.

create table if not exists public.document_files (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents(id) on delete cascade,
  url text not null,                         -- storage path in the `documents` bucket
  name text not null,
  kind text not null default 'file',         -- photo / pdf / scan / file
  mime_type text,
  size bigint,
  page_count int,
  version int not null default 1,            -- bumped when a file is replaced (D5)
  created_at timestamptz not null default now()
);

create index if not exists idx_document_files_document
  on public.document_files (document_id, created_at desc);

alter table public.document_files enable row level security;

-- Visibility is inherited from the parent document: the subquery over
-- public.documents runs with that table's RLS applied for the current user,
-- so a row here is reachable exactly when its parent document is — property
-- members and members the document was explicitly shared with, nothing else.
drop policy if exists document_files_access on public.document_files;
create policy document_files_access on public.document_files
  for all to authenticated
  using (exists (select 1 from public.documents d where d.id = document_id))
  with check (exists (select 1 from public.documents d where d.id = document_id));
