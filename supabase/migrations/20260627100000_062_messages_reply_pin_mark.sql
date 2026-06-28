-- 062: WhatsApp-style message interactions — reply, pin, mark.
alter table public.messages
  add column if not exists reply_to uuid references public.messages(id) on delete set null,
  add column if not exists pinned boolean not null default false,
  add column if not exists is_marked boolean not null default false;
