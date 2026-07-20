-- 129: Document Intelligence, phase D5 (part 2) — file versioning.
--
-- Replacing an attachment must never lose the old one. A "Replace" keeps the
-- prior file addressable and stacks a newer version on top, so a re-signed
-- contract, a renewed policy PDF or a corrected scan carries its full history.
--
-- Model: every file belongs to a `version_group` (files that occupy the same
-- logical slot share it). The newest file in a group is the "current" one;
-- older ones carry `superseded_at` + `superseded_by` (the id of the file that
-- replaced them). All additive and nullable, so pre-129 rows and older clients
-- keep working unchanged.

alter table public.document_files
  add column if not exists version_group uuid,
  add column if not exists superseded_at timestamptz,
  add column if not exists superseded_by  uuid;

-- Every existing file becomes its own group head.
update public.document_files
  set version_group = id
  where version_group is null;

-- New inserts (from any client — iOS, web) default the group to the row's own
-- id when the caller doesn't set it, so grouping is guaranteed populated and
-- the app never has to round-trip a follow-up update just to seed it.
create or replace function public.document_files_set_version_group()
returns trigger
language plpgsql
as $$
begin
  if new.version_group is null then
    new.version_group := new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_document_files_version_group on public.document_files;
create trigger trg_document_files_version_group
  before insert on public.document_files
  for each row
  execute function public.document_files_set_version_group();

-- History lookups fetch a group's versions newest-first.
create index if not exists idx_document_files_group
  on public.document_files (version_group, version desc);

-- No RLS change: the existing document_files_access policy (migration 123)
-- already scopes every row to the parent document's visibility, and these
-- columns inherit it.
