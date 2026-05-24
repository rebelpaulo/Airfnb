-- airfnb_17: extra truck fields required by the 4-step registration wizard
-- and normalization of truck_documents.kind to a known vocabulary.
--
-- Adds:
--   cuisine_types       text[]                  — Tipos de Cozinha (chips with country flags in UI)
--   dietary_options     airfnb_dietary_tag[]    — Dietas Especiais chips (vegan, vegetarian, gluten_free)
--   teardown_minutes    int                     — Tempo de desmontagem (paired with existing setup_minutes)
--   sanitation_required text                    — "none" / "wc_proximo" / "wc_dedicado"
--
-- Normalizes airfnb_truck_documents.kind to a fixed enum so the wizard's 4 PDF
-- drop zones (ASAE / Comercial / Finanças / Outros) map 1:1 to rows. Keeps
-- backwards compatibility with the existing free-text 'kind' values by mapping
-- known synonyms (haccp / seguro / insurance) into 'asae' / 'outros'.

alter table public.airfnb_trucks
  add column if not exists cuisine_types       text[]               default '{}',
  add column if not exists dietary_options     airfnb_dietary_tag[] default '{}',
  add column if not exists teardown_minutes    int                  default 60,
  add column if not exists sanitation_required text                 default 'none';

-- Constrain sanitation_required to a small vocabulary
do $$ begin
  alter table public.airfnb_trucks
    add constraint airfnb_trucks_sanitation_required_chk
    check (sanitation_required in ('none','wc_proximo','wc_dedicado'));
exception when duplicate_object then null;
end $$;

-- Document kind enum (the 4 drop zones in step 4)
do $$ begin
  create type airfnb_truck_document_kind as enum ('asae','comercial','financas','outros');
exception when duplicate_object then null;
end $$;

-- Map legacy free-text values into the new vocabulary before swapping the type.
-- Anything that doesn't match a known synonym lands in 'outros' rather than
-- being deleted — we never want to lose an uploaded doc reference.
update public.airfnb_truck_documents
   set kind = case
     when lower(coalesce(kind,'')) ~ 'asae|haccp|saude|sanit' then 'asae'
     when lower(coalesce(kind,'')) ~ 'comerc|registo|iban'    then 'comercial'
     when lower(coalesce(kind,'')) ~ 'finan|nif|iva|fact'     then 'financas'
     else 'outros'
   end;

alter table public.airfnb_truck_documents
  alter column kind drop default;
alter table public.airfnb_truck_documents
  alter column kind type airfnb_truck_document_kind using kind::airfnb_truck_document_kind;
alter table public.airfnb_truck_documents
  alter column kind set default 'outros';

-- Helpful index: most truck queries pivot on owner + status; the wizard checks
-- "does this owner already have an active truck?" frequently.
create index if not exists airfnb_trucks_owner_status_idx
  on public.airfnb_trucks (owner_id, status);
