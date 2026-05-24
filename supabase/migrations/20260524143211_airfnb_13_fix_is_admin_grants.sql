-- airfnb_13_fix_is_admin_grants
-- applied at 20260524143211


-- airfnb_is_admin is referenced in RLS policies. RLS evaluates as the calling role,
-- so anon and authenticated MUST be able to execute it. The function itself is safe
-- (returns boolean based on profile lookup with security definer).
grant execute on function public.airfnb_is_admin() to anon, authenticated;
;
