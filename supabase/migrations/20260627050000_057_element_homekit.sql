-- 057: Link a property element to a HomeKit accessory (by uniqueIdentifier).
alter table public.property_elements
  add column if not exists homekit_accessory_id text;
