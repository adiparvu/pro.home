-- 173: "Văzut ultima dată" pe pagina publică + index pentru documentele
-- legate de obiecte de inventar.

-- Pagina publică (Cloudflare worker, cheie publishable/anon) marchează
-- fiecare vizualizare; aplicația arată proprietarului momentul ultimei
-- scanări a etichetei QR.
alter table public.public_items
  add column if not exists last_scanned_at timestamptz;

-- RPC îngust, apelabil anonim de pe pagina publică. SECURITY DEFINER
-- strict pe un singur UPDATE de timestamp — nu citește și nu returnează
-- nimic, nu acceptă alte coloane, deci suprafața publică e minimă.
create or replace function public.note_item_scan(p_item_uuid uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.public_items
     set last_scanned_at = now()
   where item_uuid = p_item_uuid;
$$;

revoke all on function public.note_item_scan(uuid) from public;
grant execute on function public.note_item_scan(uuid) to anon, authenticated;

-- Documentele se pot lega de un obiect de inventar (coloana există din
-- migrarea care a introdus inventory_item_id); indexul lipsea.
create index if not exists documents_inventory_item_id_idx
  on public.documents (inventory_item_id)
  where inventory_item_id is not null;
