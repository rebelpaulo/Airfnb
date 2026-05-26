-- Break the infinite-recursion loop between airfnb_event_requests and
-- airfnb_request_invitations SELECT policies.
--
-- The loop:
--   airfnb_event_requests.airfnb_req_public_read does EXISTS over
--   airfnb_request_invitations → which triggers its own SELECT policy
--   airfnb_inv_read → which does EXISTS over airfnb_event_requests → loop.
--
-- This was latent until /publicar's `INSERT ... .select("id").single()`
-- path started exercising the SELECT policy on the returned row (PostgREST
-- runs the RETURNING through the SELECT policy). Symptom in the wizard:
-- "Finalizar" errored with "infinite recursion detected in policy for
-- relation airfnb_event_requests".
--
-- Fix: replace the cross-table EXISTS subqueries in both policies with
-- SECURITY DEFINER helper functions. SECURITY DEFINER bypasses RLS on the
-- inner SELECT, so the policy on table A no longer re-enters table B's
-- policy (which would re-enter A's policy, etc.).

-- =========================================================================
-- 1. Helper: is the current user the owner of a truck invited to request X?
-- =========================================================================
create or replace function public.airfnb_user_owns_invited_truck(p_request uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.airfnb_request_invitations ri
      join public.airfnb_trucks t on t.id = ri.truck_id
     where ri.request_id = p_request
       and t.owner_id    = auth.uid()
  )
$$;
-- Anon needs EXECUTE too: airfnb_event_requests has a public-read path
-- (visibility='public' + status in [...]) that anon users can hit, and
-- Postgres evaluates the WHOLE policy expression — including any function
-- calls in OR branches — so the role must be allowed to call them even
-- if the short-circuit never reaches the helper. SECURITY DEFINER keeps
-- the inner SELECT safe regardless of caller.
revoke execute on function public.airfnb_user_owns_invited_truck(uuid) from public;
grant  execute on function public.airfnb_user_owns_invited_truck(uuid) to anon, authenticated, service_role;

-- =========================================================================
-- 2. Helper: is the current user the organizer of request X?
--    Trivial — no cross-table — but wrapping it as a function keeps both
--    policies consistent and lets us swap implementation later if needed.
-- =========================================================================
create or replace function public.airfnb_user_organizes_request(p_request uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.airfnb_event_requests r
     where r.id           = p_request
       and r.organizer_id = auth.uid()
  )
$$;
revoke execute on function public.airfnb_user_organizes_request(uuid) from public;
grant  execute on function public.airfnb_user_organizes_request(uuid) to anon, authenticated, service_role;

-- =========================================================================
-- 3. Rewrite airfnb_event_requests SELECT policy
-- =========================================================================
drop policy if exists airfnb_req_public_read on public.airfnb_event_requests;
create policy airfnb_req_public_read on public.airfnb_event_requests
  for select
  using (
    (
      visibility = 'public'
      and status in ('open'::airfnb_request_status, 'reviewing'::airfnb_request_status, 'awarded'::airfnb_request_status)
    )
    or organizer_id = auth.uid()
    or public.airfnb_is_admin()
    or public.airfnb_user_owns_invited_truck(id)
  );

-- =========================================================================
-- 4. Rewrite airfnb_request_invitations SELECT policy
-- =========================================================================
drop policy if exists airfnb_inv_read on public.airfnb_request_invitations;
create policy airfnb_inv_read on public.airfnb_request_invitations
  for select
  using (
    public.airfnb_is_admin()
    or exists (
         select 1 from public.airfnb_trucks t
          where t.id = airfnb_request_invitations.truck_id
            and t.owner_id = auth.uid()
       )
    or public.airfnb_user_organizes_request(request_id)
  );
