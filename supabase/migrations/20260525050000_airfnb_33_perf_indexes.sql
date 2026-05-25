-- airfnb_33: performance indexes on the hot read paths.
--
-- Catalog queries: status='active' + filters (city, capacity, rating).
-- Most-recent-messages-per-conversation: (conversation_id, created_at desc).
-- Notifications dropdown: (user_id, read_at is null, created_at desc).
-- Bookings cron sweep: (status, due_until) lock_fees idx already exists.

-- Catalog: trucks browse pages always filter status='active' and sort by
-- rating. Existing airfnb_trucks_active_idx is partial on status='active'
-- only; adding rating to the composite avoids a sort when serving the grid.
create index if not exists airfnb_trucks_active_rating_idx
  on public.airfnb_trucks (rating_avg desc, id)
  where status = 'active';

-- Catalog city filter: ilike '%city%' won't use a btree, so add a trigram
-- index. pg_trgm is enabled in this project (seen earlier).
create extension if not exists pg_trgm;
create index if not exists airfnb_trucks_base_city_trgm_idx
  on public.airfnb_trucks using gin (base_city gin_trgm_ops);

-- Messages: ChatClient + conversa list both order by (conversation_id, created_at).
-- The existing airfnb_messages_conv_idx covers (conversation_id, created_at)
-- but doesn't help DESC scans — add a brin idx to keep newest cheap to find.
create index if not exists airfnb_messages_created_at_brin
  on public.airfnb_messages using brin (created_at);

-- Notifications dropdown: filter user_id + unread + order by created_at desc.
create index if not exists airfnb_notifications_user_unread_idx
  on public.airfnb_notifications (user_id, created_at desc)
  where read_at is null;

-- Event requests browse (oportunidades): status='open' + start_at >= now()
create index if not exists airfnb_event_requests_open_start_idx
  on public.airfnb_event_requests (start_at)
  where status = 'open';
