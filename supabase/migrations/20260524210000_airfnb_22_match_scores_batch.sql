-- airfnb_22: batch flavor of airfnb_match_score for the truck-owner
-- oportunidades feed.
--
-- The per-pair function is fine for one-off scoring, but the feed needs to
-- score (owner's trucks) × (open requests) — up to ~10 × ~80 in practice.
-- Calling the RPC per pair forces serialized round-trips. This function
-- runs it in one SQL pass, returning only positive scores so the caller
-- can filter cheaply on the JS side.

create or replace function public.airfnb_match_scores_batch(
  p_truck_ids   uuid[],
  p_request_ids uuid[]
)
returns table (
  truck_id    uuid,
  request_id  uuid,
  score       numeric
)
language sql
stable
security invoker
set search_path = public
as $$
  select t.id, r.id, public.airfnb_match_score(t.id, r.id) as score
    from public.airfnb_trucks t
    cross join public.airfnb_event_requests r
   where t.id  = any(p_truck_ids)
     and r.id  = any(p_request_ids)
     and public.airfnb_match_score(t.id, r.id) > 0
$$;

revoke execute on function public.airfnb_match_scores_batch(uuid[], uuid[]) from public, anon;
grant  execute on function public.airfnb_match_scores_batch(uuid[], uuid[]) to authenticated;
