-- airfnb_28: lock down airfnb_check_rate_limit so authenticated users
-- can't poison counters belonging to other users.
--
-- The function is SECURITY DEFINER and was previously granted EXECUTE to
-- authenticated for the client precheck. After migration 27 the BEFORE
-- INSERT triggers are the only legitimate callers; both run as the function
-- owner (postgres) and don't need direct grants. Revoking from authenticated
-- removes the DoS vector where a user could iterate
-- airfnb_check_rate_limit('event_request_create', '<other-user-uuid>', 1, 86400)
-- to exhaust another organizer's daily quota.

revoke execute on function public.airfnb_check_rate_limit(text, text, int, int)
  from public, anon, authenticated;
