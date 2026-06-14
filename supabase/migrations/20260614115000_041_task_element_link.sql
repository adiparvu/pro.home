-- Digital Property Twin — link maintenance tasks to objects
alter table public.maintenance_tasks
    add column if not exists element_id uuid references public.property_elements(id) on delete set null;

create index if not exists maintenance_tasks_element_id_idx on public.maintenance_tasks (element_id);
