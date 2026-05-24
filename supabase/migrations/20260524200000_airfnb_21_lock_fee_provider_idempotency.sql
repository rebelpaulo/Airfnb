-- airfnb_21: harden airfnb_lock_fees for Stripe Checkout integration.
--
-- - provider_event_log JSONB:  append-only audit of webhook events (one
--   object per event with id/type/received_at). Lets us debug "why didn't
--   this transition" without leaving Stripe.
-- - unique partial idx on provider_ref:  the webhook handler is the only
--   thing that writes provider_ref, and Stripe can replay events at-least-
--   once. The unique idx blocks duplicate writes; the handler relies on
--   ON CONFLICT … DO NOTHING via the `provider_ref` slot.
-- - composite idx (status, due_until):  the cron sweep selects
--   'pending' rows where `due_until < now()` to expire / refund.

alter table public.airfnb_lock_fees
  add column if not exists provider_event_log jsonb not null default '[]'::jsonb;

create unique index if not exists airfnb_lock_fees_provider_ref_uniq
  on public.airfnb_lock_fees (provider_ref)
  where provider_ref is not null;

create index if not exists airfnb_lock_fees_status_due_idx
  on public.airfnb_lock_fees (status, due_until);
