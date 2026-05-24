-- airfnb_14_slots_needed_null_default_and_payments_provider_ref_unique
-- applied at 20260524160100

-- 1. slots_needed default NULL so the trigger can distinguish
--    "user explicitly set 1" from "column defaulted to 1".
alter table public.airfnb_event_requests
  alter column slots_needed drop default,
  alter column slots_needed drop not null;

create or replace function public.airfnb_set_recommended_slots() returns trigger
  language plpgsql security invoker set search_path = public as $$
begin
  if new.recommended_slots is null and new.kind is not null and new.expected_pax is not null then
    new.recommended_slots := public.airfnb_recommend_slots(new.kind, new.expected_pax);
  end if;
  if new.slots_needed is null then
    new.slots_needed := coalesce(new.recommended_slots, 1);
  end if;
  return new;
end $$;

-- 2. unique index on airfnb_payments.provider_ref so stripe webhook retries
--    can use ON CONFLICT (provider_ref) safely.
create unique index if not exists airfnb_payments_provider_ref_unique
  on public.airfnb_payments(provider_ref)
  where provider_ref is not null;
