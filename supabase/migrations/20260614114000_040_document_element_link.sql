-- Digital Property Twin — link documents to objects
alter table public.documents
    add column if not exists element_id uuid references public.property_elements(id) on delete set null;

create index if not exists documents_element_id_idx on public.documents (element_id);
