-- Reconcile the marketplace decision boundary after privacy, messaging,
-- Storage and catalog. The migration is one fail-closed transaction and is
-- intentionally limited to the application -> booking -> lock-fee workflow.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local idle_in_transaction_session_timeout = '60s';

lock table
  public.airfnb_event_requests,
  public.airfnb_applications,
  public.airfnb_bookings,
  public.airfnb_booking_trucks,
  public.airfnb_lock_fees,
  public.airfnb_request_invitations,
  public.airfnb_trucks,
  public.airfnb_conversations,
  public.airfnb_conversation_participants,
  public.airfnb_notifications,
  public.airfnb_platform_settings
in access exclusive mode;

create temporary table airfnb_marketplace_protected_functions_20260820
on commit drop as
select procedure.oid,
       procedure.proowner,
       procedure.proacl,
       procedure.prosecdef,
       procedure.provolatile,
       procedure.proconfig,
       pg_catalog.md5(procedure.prosrc) as body_hash
  from pg_catalog.pg_proc as procedure
  join pg_catalog.pg_namespace as namespace
    on namespace.oid = procedure.pronamespace
 where namespace.nspname = 'public'
   and procedure.proname in (
     'airfnb_calculate_lock_fee',
     'airfnb_setting_int',
     'airfnb_match_score',
     'airfnb_match_category_availability_score',
     'airfnb_mark_conversation_read',
     'airfnb_prepare_truck_review',
     'airfnb_prepare_organizer_review',
     'airfnb_recalc_truck_rating',
     'airfnb_guard_truck_moderation',
     'airfnb_can_manage_truck',
     'airfnb_can_submit_application',
     'airfnb_own_application_truck',
     'airfnb_can_read_truck_child',
     'airfnb_reconcile_stripe_event'
   );

create temporary table airfnb_marketplace_protected_relations_20260820
on commit drop as
select relation.oid,
       relation.relowner,
       relation.relacl,
       relation.relrowsecurity,
       relation.relforcerowsecurity
  from pg_catalog.pg_class as relation
 where relation.oid in (
   'public.airfnb_event_requests'::pg_catalog.regclass,
   'public.airfnb_trucks'::pg_catalog.regclass,
   'public.airfnb_conversations'::pg_catalog.regclass,
   'public.airfnb_conversation_participants'::pg_catalog.regclass,
   'public.airfnb_notifications'::pg_catalog.regclass,
   'public.airfnb_truck_images'::pg_catalog.regclass,
   'public.airfnb_truck_categories'::pg_catalog.regclass,
   'public.airfnb_categories'::pg_catalog.regclass,
   'public.airfnb_v_truck_card'::pg_catalog.regclass
 );

create temporary table airfnb_marketplace_protected_policies_20260820
on commit drop as
select policy.oid,
       policy.polrelid,
       policy.polname,
       policy.polcmd,
       policy.polpermissive,
       policy.polroles,
       pg_catalog.pg_get_expr(policy.polqual, policy.polrelid) as using_expression,
       pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid) as check_expression
  from pg_catalog.pg_policy as policy
 where policy.polrelid in (
   'public.airfnb_event_requests'::pg_catalog.regclass,
   'public.airfnb_trucks'::pg_catalog.regclass,
   'public.airfnb_conversations'::pg_catalog.regclass,
   'public.airfnb_conversation_participants'::pg_catalog.regclass,
   'public.airfnb_notifications'::pg_catalog.regclass,
   'public.airfnb_lock_fees'::pg_catalog.regclass,
   'public.airfnb_truck_images'::pg_catalog.regclass,
   'public.airfnb_truck_categories'::pg_catalog.regclass,
   'public.airfnb_categories'::pg_catalog.regclass
 );

do $preconditions$
declare
  v_owner oid := (
    select relation.relowner
      from pg_catalog.pg_class as relation
     where relation.oid = 'public.airfnb_applications'::pg_catalog.regclass
  );
  v_anon oid := (select oid from pg_catalog.pg_roles where rolname = 'anon');
  v_authenticated oid := (select oid from pg_catalog.pg_roles where rolname = 'authenticated');
  v_service_role oid := (select oid from pg_catalog.pg_roles where rolname = 'service_role');
  v_final boolean := pg_catalog.to_regprocedure(
    'public.airfnb_supplier_lock_fee(uuid)'
  ) is not null;
  v_submit_helper boolean := pg_catalog.to_regprocedure(
    'public.airfnb_can_submit_application(uuid,uuid)'
  ) is not null;
  v_own_truck_helper boolean := pg_catalog.to_regprocedure(
    'public.airfnb_own_application_truck()'
  ) is not null;
  v_policy_names name[];
begin
  if v_owner is null or v_anon is null or v_authenticated is null
     or v_service_role is null then
    raise exception 'marketplace reconciliation refused: required owner or API role is missing';
  end if;

  if v_owner <> (select oid from pg_catalog.pg_roles where rolname = current_user)
     or exists (
       select 1
         from unnest(array[
           'public.airfnb_event_requests'::pg_catalog.regclass,
           'public.airfnb_bookings'::pg_catalog.regclass,
           'public.airfnb_booking_trucks'::pg_catalog.regclass,
           'public.airfnb_lock_fees'::pg_catalog.regclass,
           'public.airfnb_request_invitations'::pg_catalog.regclass,
           'public.airfnb_trucks'::pg_catalog.regclass,
           'public.airfnb_conversations'::pg_catalog.regclass,
           'public.airfnb_conversation_participants'::pg_catalog.regclass,
           'public.airfnb_notifications'::pg_catalog.regclass,
           'public.airfnb_platform_settings'::pg_catalog.regclass
         ]) as target(relation_oid)
         join pg_catalog.pg_class as relation on relation.oid = target.relation_oid
        where relation.relowner <> v_owner
     ) then
    raise exception 'marketplace reconciliation refused: owner alignment drifted';
  end if;

  if exists (
    select 1
      from unnest(array[
        'public.airfnb_event_requests'::pg_catalog.regclass,
        'public.airfnb_applications'::pg_catalog.regclass,
        'public.airfnb_bookings'::pg_catalog.regclass,
        'public.airfnb_booking_trucks'::pg_catalog.regclass,
        'public.airfnb_lock_fees'::pg_catalog.regclass,
        'public.airfnb_request_invitations'::pg_catalog.regclass,
        'public.airfnb_trucks'::pg_catalog.regclass,
        'public.airfnb_conversations'::pg_catalog.regclass,
        'public.airfnb_conversation_participants'::pg_catalog.regclass,
        'public.airfnb_notifications'::pg_catalog.regclass
      ]) as target(relation_oid)
      join pg_catalog.pg_class as relation on relation.oid = target.relation_oid
     where relation.relkind <> 'r'
        or not relation.relrowsecurity
        or relation.relforcerowsecurity
  ) then
    raise exception 'marketplace reconciliation refused: relation or RLS mode drifted';
  end if;

  if (select pg_catalog.count(*) from pg_catalog.pg_attribute
       where attrelid = 'public.airfnb_event_requests'::pg_catalog.regclass
         and attnum > 0 and not attisdropped) <> 50
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute
          where attrelid = 'public.airfnb_applications'::pg_catalog.regclass
            and attnum > 0 and not attisdropped) <> 17
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute
          where attrelid = 'public.airfnb_bookings'::pg_catalog.regclass
            and attnum > 0 and not attisdropped) <> 15
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute
          where attrelid = 'public.airfnb_booking_trucks'::pg_catalog.regclass
            and attnum > 0 and not attisdropped) <> 4
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute
          where attrelid = 'public.airfnb_lock_fees'::pg_catalog.regclass
            and attnum > 0 and not attisdropped) <> 13
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute
          where attrelid = 'public.airfnb_conversations'::pg_catalog.regclass
            and attnum > 0 and not attisdropped) <> 4
     or (select pg_catalog.count(*) from pg_catalog.pg_attribute
          where attrelid = 'public.airfnb_conversation_participants'::pg_catalog.regclass
            and attnum > 0 and not attisdropped) <> 3 then
    raise exception 'marketplace reconciliation refused: schema shape drifted';
  end if;

  if not exists (
       select 1 from pg_catalog.pg_attribute
        where attrelid = 'public.airfnb_bookings'::pg_catalog.regclass
          and attname = 'application_id' and atttypid = 'uuid'::pg_catalog.regtype
          and not attnotnull
     ) or not exists (
       select 1 from pg_catalog.pg_attribute
        where attrelid = 'public.airfnb_bookings'::pg_catalog.regclass
          and attname = 'ics_token' and atttypid = 'text'::pg_catalog.regtype
          and not attnotnull
     ) or not exists (
       select 1 from pg_catalog.pg_attribute
        where attrelid = 'public.airfnb_lock_fees'::pg_catalog.regclass
          and attname = 'provider_event_log' and atttypid = 'jsonb'::pg_catalog.regtype
          and attnotnull
     ) then
    raise exception 'marketplace reconciliation refused: booking or fee columns drifted';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc as procedure
     where procedure.oid = 'public.airfnb_is_admin()'::pg_catalog.regprocedure
       and procedure.proowner = v_owner
       and procedure.prosecdef
       and procedure.provolatile = 's'
       and procedure.proconfig = array['search_path=""']::text[]
       and pg_catalog.md5(procedure.prosrc) = 'aa950c573de3ffe4835f7851c09a0631'
  ) or not exists (
    select 1 from pg_catalog.pg_proc as procedure
     where procedure.oid = 'public.airfnb_calculate_lock_fee(uuid)'::pg_catalog.regprocedure
       and procedure.proowner = v_owner
       and procedure.prosecdef
       and procedure.provolatile = 's'
       and procedure.proconfig = array['search_path=public']::text[]
       and procedure.prorettype = 'jsonb'::pg_catalog.regtype
       and pg_catalog.md5(procedure.prosrc) = '5955bc4f93e2f63ff040f47a756ff58f'
       and not pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
       and not pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
       and pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
  ) or not exists (
    select 1 from pg_catalog.pg_proc as procedure
     where procedure.oid = 'public.airfnb_can_manage_truck(text)'::pg_catalog.regprocedure
       and procedure.proowner = v_owner
       and procedure.prosecdef
       and procedure.provolatile = 's'
       and procedure.proconfig = array['search_path=""']::text[]
       and pg_catalog.md5(procedure.prosrc) = '982caee25d35d0ac9dfe1d3a343ab0a5'
       and pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
       and not pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
       and not pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
  ) then
    raise exception 'marketplace reconciliation refused: privacy, fee or catalog helper drifted';
  end if;

  if not v_final and not exists (
    select 1 from pg_catalog.pg_proc as procedure
     where procedure.oid = 'public.airfnb_accept_application(uuid)'::pg_catalog.regprocedure
       and procedure.proowner = v_owner and procedure.prosecdef
       and procedure.provolatile = 'v'
       and procedure.proconfig = array['search_path=pg_catalog, public']::text[]
       and pg_catalog.md5(procedure.prosrc) = 'b7c875f8b312e246e2f4621f5748b0a1'
  ) then
    raise exception 'marketplace reconciliation refused: messaging accept predecessor drifted';
  end if;

  if (not v_final and v_submit_helper)
     or (v_final and not exists (
       select 1 from pg_catalog.pg_proc as procedure
        where procedure.oid = pg_catalog.to_regprocedure(
          'public.airfnb_can_submit_application(uuid,uuid)'
        )
          and procedure.proowner = v_owner
          and procedure.prosecdef
          and procedure.provolatile = 's'
          and procedure.proconfig = array['search_path=""']::text[]
          and procedure.prorettype = 'boolean'::pg_catalog.regtype
          and pg_catalog.md5(procedure.prosrc) = 'c96f49df5f1b05fabea73bfdbf534a74'
          and pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
          and not pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
          and not pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
          and not exists (
            select 1
              from pg_catalog.aclexplode(
                coalesce(procedure.proacl, pg_catalog.acldefault('f', procedure.proowner))
              ) as privilege
             where privilege.privilege_type = 'EXECUTE'
               and privilege.grantee not in (procedure.proowner, v_authenticated)
          )
     )) then
    raise exception 'marketplace reconciliation refused: application submission helper drifted';
  end if;

  if (not v_final and v_own_truck_helper)
     or (v_final and not exists (
       select 1 from pg_catalog.pg_proc as procedure
        where procedure.oid = pg_catalog.to_regprocedure(
          'public.airfnb_own_application_truck()'
        )
          and procedure.proowner = v_owner
          and procedure.prosecdef
          and procedure.provolatile = 's'
          and procedure.proconfig = array['search_path=""']::text[]
          and procedure.proretset
          and procedure.proallargtypes = array[
            'uuid'::pg_catalog.regtype,
            'text'::pg_catalog.regtype,
            'public.airfnb_truck_status'::pg_catalog.regtype
          ]::oid[]
          and procedure.proargmodes = array['t','t','t']::"char"[]
          and procedure.proargnames = array[
            'truck_id','truck_name','truck_status'
          ]::text[]
          and pg_catalog.md5(procedure.prosrc) = 'f8b910f51897ceb6b4fea4e1b049d02b'
          and pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
          and not pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
          and not pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
          and not exists (
            select 1
              from pg_catalog.aclexplode(
                coalesce(procedure.proacl, pg_catalog.acldefault('f', procedure.proowner))
              ) as privilege
             where privilege.privilege_type = 'EXECUTE'
               and privilege.grantee not in (procedure.proowner, v_authenticated)
          )
     )) then
    raise exception 'marketplace reconciliation refused: own application truck helper drifted';
  end if;

  select pg_catalog.array_agg(policy.polname order by policy.polname)
    into v_policy_names
    from pg_catalog.pg_policy as policy
   where policy.polrelid = 'public.airfnb_applications'::pg_catalog.regclass;
  if (not v_final and v_policy_names is distinct from
      array['airfnb_app_insert','airfnb_app_read']::name[])
     or (v_final and v_policy_names is distinct from
      array['airfnb_app_insert_guarded','airfnb_app_select_participant']::name[]) then
    raise exception 'marketplace reconciliation refused: application policy catalog drifted';
  end if;

  if exists (
    select application.id
      from public.airfnb_applications as application
      join public.airfnb_bookings as booking
        on booking.application_id = application.id
     group by application.id
    having pg_catalog.count(*) > 1
  ) or exists (
    select 1 from public.airfnb_applications where status is null
  ) or exists (
    select 1 from public.airfnb_event_requests
     where status is null
        or slots_needed is null or slots_needed not between 1 and 10
        or application_response_window_hours is null
        or application_response_window_hours <= 0
  ) or exists (
    select 1 from public.airfnb_lock_fees
     where amount < 0 or platform_fee < 0 or organizer_share < 0
        or amount is distinct from platform_fee + organizer_share
  ) then
    raise exception 'marketplace reconciliation refused: existing workflow data is ambiguous';
  end if;

  if not v_final and pg_catalog.to_regclass(
       'public.airfnb_bookings_application_unique'
     ) is not null then
    raise exception 'marketplace reconciliation refused: partial predecessor index state';
  end if;

  if v_final and not exists (
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public' and tablename = 'airfnb_bookings'
       and indexname = 'airfnb_bookings_application_unique'
       and indexdef = 'CREATE UNIQUE INDEX airfnb_bookings_application_unique ON public.airfnb_bookings USING btree (application_id) WHERE (application_id IS NOT NULL)'
  ) then
    raise exception 'marketplace reconciliation refused: final booking uniqueness drifted';
  end if;
end
$preconditions$;

create unique index if not exists airfnb_bookings_application_unique
  on public.airfnb_bookings(application_id)
  where application_id is not null;

create or replace function public.airfnb_can_submit_application(
  p_request uuid,
  p_truck uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select auth.uid() is not null
    and exists (
      select 1
        from public.airfnb_trucks as truck
        join public.airfnb_event_requests as request_row
          on request_row.id = p_request
       where truck.id = p_truck
         and truck.owner_id = auth.uid()
         and truck.status = 'active'::public.airfnb_truck_status
         and request_row.status = 'open'::public.airfnb_request_status
         and request_row.start_at > pg_catalog.now()
         and (
           request_row.applications_deadline is null
           or request_row.applications_deadline > pg_catalog.now()
         )
         and (
           request_row.visibility = 'public'
           or exists (
             select 1
               from public.airfnb_request_invitations as invitation
              where invitation.request_id = request_row.id
                and invitation.truck_id = truck.id
           )
         )
    )
$function$;

revoke all on function public.airfnb_can_submit_application(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_can_submit_application(uuid, uuid)
  to authenticated;

create or replace function public.airfnb_own_application_truck()
returns table (
  truck_id uuid,
  truck_name text,
  truck_status public.airfnb_truck_status
)
language sql
stable
security definer
set search_path = ''
as $function$
  select truck.id, truck.name, truck.status
    from public.airfnb_trucks as truck
   where auth.uid() is not null
     and coalesce(
       pg_catalog.current_setting('request.jwt.claim.role', true), ''
     ) <> 'service_role'
     and truck.owner_id = auth.uid()
   order by truck.created_at, truck.id
   limit 1
$function$;

revoke all on function public.airfnb_own_application_truck()
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_own_application_truck()
  to authenticated;

drop policy if exists "airfnb_app_read" on public.airfnb_applications;
drop policy if exists "airfnb_app_insert" on public.airfnb_applications;
drop policy if exists "airfnb_app_select_participant" on public.airfnb_applications;
drop policy if exists "airfnb_app_insert_guarded" on public.airfnb_applications;

create policy "airfnb_app_select_participant"
  on public.airfnb_applications
  for select
  to authenticated
  using (
    (select public.airfnb_is_admin())
    or (select public.airfnb_can_manage_truck(airfnb_applications.truck_id::text))
    or exists (
      select 1
        from public.airfnb_event_requests as request_row
       where request_row.id = airfnb_applications.request_id
         and request_row.organizer_id = (select auth.uid())
    )
  );

create policy "airfnb_app_insert_guarded"
  on public.airfnb_applications
  for insert
  to authenticated
  with check (
    status = 'submitted'::public.airfnb_application_status
    and shortlisted_at is null
    and decided_at is null
    and withdrawn_at is null
    and (select public.airfnb_can_submit_application(
      airfnb_applications.request_id,
      airfnb_applications.truck_id
    ))
  );

revoke all on table public.airfnb_applications
  from public, anon, authenticated, service_role;
grant select on table public.airfnb_applications to authenticated;
grant insert (
  request_id, truck_id, proposed_price, cover_message, menu_pitch,
  estimated_servings, available_confirmed, deal_type,
  proposed_fixed_to_organizer, proposed_revenue_share_pct
) on table public.airfnb_applications to authenticated;
grant select, insert, update, delete on table public.airfnb_applications
  to service_role;

revoke all on table public.airfnb_bookings
  from public, anon, authenticated, service_role;
grant select on table public.airfnb_bookings to authenticated;
grant select, insert, update, delete on table public.airfnb_bookings
  to service_role;

revoke all on table public.airfnb_booking_trucks
  from public, anon, authenticated, service_role;
grant select on table public.airfnb_booking_trucks to authenticated;
grant select, insert, update, delete on table public.airfnb_booking_trucks
  to service_role;

revoke all on table public.airfnb_lock_fees
  from public, anon, authenticated, service_role;
grant select, insert, update, delete on table public.airfnb_lock_fees
  to service_role;

create or replace function public.airfnb_shortlist_application(p_application uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_application public.airfnb_applications%rowtype;
  v_request public.airfnb_event_requests%rowtype;
  v_actor uuid := auth.uid();
  v_signed_service_role boolean := coalesce(
    current_setting('request.jwt.claim.role', true), ''
  ) = 'service_role';
begin
  select * into v_application
    from public.airfnb_applications
   where id = p_application
   for update;
  if not found then
    raise exception using errcode = '22023', message = 'application not found';
  end if;

  select * into v_request
    from public.airfnb_event_requests
   where id = v_application.request_id
   for update;
  if not found then
    raise exception using errcode = '55000', message = 'request not found';
  end if;

  if not v_signed_service_role and (
    v_actor is null or (
      v_actor is distinct from v_request.organizer_id
      and not public.airfnb_is_admin()
    )
  ) then
    raise exception using errcode = '42501', message = 'not authorized';
  end if;
  if v_request.status is null or v_request.status not in ('open', 'reviewing') then
    raise exception using errcode = '55000',
      message = 'request is not reviewing applications';
  end if;
  if v_application.status is null or v_application.status <> 'submitted' then
    raise exception using errcode = '55000',
      message = 'application is not eligible for shortlist';
  end if;

  update public.airfnb_applications
     set status = 'shortlisted', shortlisted_at = pg_catalog.statement_timestamp()
   where id = v_application.id;

  insert into public.airfnb_notifications(user_id, kind, payload)
  select truck.owner_id,
         'application.shortlisted',
         pg_catalog.jsonb_build_object(
           'application_id', v_application.id,
           'request_id', v_request.id,
           'request_title', v_request.title
         )
    from public.airfnb_trucks as truck
   where truck.id = v_application.truck_id;
end
$function$;

create or replace function public.airfnb_reject_application(
  p_application uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_application public.airfnb_applications%rowtype;
  v_request public.airfnb_event_requests%rowtype;
  v_actor uuid := auth.uid();
  v_signed_service_role boolean := coalesce(
    current_setting('request.jwt.claim.role', true), ''
  ) = 'service_role';
begin
  select * into v_application
    from public.airfnb_applications
   where id = p_application
   for update;
  if not found then
    raise exception using errcode = '22023', message = 'application not found';
  end if;

  select * into v_request
    from public.airfnb_event_requests
   where id = v_application.request_id
   for update;
  if not found then
    raise exception using errcode = '55000', message = 'request not found';
  end if;

  if not v_signed_service_role and (
    v_actor is null or (
      v_actor is distinct from v_request.organizer_id
      and not public.airfnb_is_admin()
    )
  ) then
    raise exception using errcode = '42501', message = 'not authorized';
  end if;
  if v_request.status is null or v_request.status not in ('open', 'reviewing', 'awarded') then
    raise exception using errcode = '55000',
      message = 'request cannot reject applications';
  end if;
  if v_application.status is null
     or v_application.status not in ('submitted', 'shortlisted') then
    raise exception using errcode = '55000',
      message = 'application is not eligible for rejection';
  end if;

  update public.airfnb_applications
     set status = 'rejected', decided_at = pg_catalog.statement_timestamp()
   where id = v_application.id;

  insert into public.airfnb_notifications(user_id, kind, payload)
  select truck.owner_id,
         'application.rejected',
         pg_catalog.jsonb_build_object(
           'application_id', v_application.id,
           'request_id', v_request.id,
           'reason', p_reason
         )
    from public.airfnb_trucks as truck
   where truck.id = v_application.truck_id;
end
$function$;

create or replace function public.airfnb_accept_application(p_application uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_application public.airfnb_applications%rowtype;
  v_request public.airfnb_event_requests%rowtype;
  v_actor uuid := auth.uid();
  v_signed_service_role boolean := coalesce(
    current_setting('request.jwt.claim.role', true), ''
  ) = 'service_role';
  v_booking_id uuid;
  v_lock_fee_id uuid;
  v_conversation_id uuid;
  v_fee jsonb;
  v_total numeric;
  v_platform numeric;
  v_organizer numeric;
  v_accepted integer;
  v_decided_at timestamptz := pg_catalog.statement_timestamp();
  v_due_until timestamptz;
begin
  select * into v_application
    from public.airfnb_applications
   where id = p_application
   for update;
  if not found then
    raise exception using errcode = '22023', message = 'application not found';
  end if;
  if v_application.status is null
     or v_application.status not in ('submitted', 'shortlisted') then
    raise exception using errcode = '55000',
      message = 'application is not eligible for acceptance';
  end if;

  select * into v_request
    from public.airfnb_event_requests
   where id = v_application.request_id
   for update;
  if not found then
    raise exception using errcode = '55000', message = 'request not found';
  end if;

  if not v_signed_service_role and (
    v_actor is null or (
      v_actor is distinct from v_request.organizer_id
      and not public.airfnb_is_admin()
    )
  ) then
    raise exception using errcode = '42501', message = 'not authorized';
  end if;
  if v_request.slots_needed is null or v_request.slots_needed not between 1 and 10
     or v_request.application_response_window_hours is null
     or v_request.application_response_window_hours <= 0 then
    raise exception using errcode = '22023',
      message = 'request acceptance settings are invalid';
  end if;

  select pg_catalog.count(*)::integer into v_accepted
    from public.airfnb_applications as accepted_application
   where accepted_application.request_id = v_request.id
     and accepted_application.status = 'accepted';
  if v_accepted >= v_request.slots_needed then
    raise exception using errcode = '55000',
      message = 'request has no remaining slots';
  end if;
  if v_request.status is null or v_request.status not in ('open', 'reviewing') then
    raise exception using errcode = '55000',
      message = 'request is not accepting applications';
  end if;

  v_fee := public.airfnb_calculate_lock_fee(v_application.id);
  if pg_catalog.jsonb_typeof(v_fee) is distinct from 'object'
     or not v_fee ?& array['platform_fee','organizer_share','total'] then
    raise exception using errcode = '22023', message = 'lock fee split is invalid';
  end if;
  v_platform := (v_fee ->> 'platform_fee')::numeric;
  v_organizer := (v_fee ->> 'organizer_share')::numeric;
  v_total := (v_fee ->> 'total')::numeric;
  if v_platform is null or v_organizer is null or v_total is null
     or v_platform::text in ('NaN','Infinity','-Infinity')
     or v_organizer::text in ('NaN','Infinity','-Infinity')
     or v_total::text in ('NaN','Infinity','-Infinity')
     or v_platform < 0 or v_organizer < 0 or v_total < 0
     or v_total is distinct from v_platform + v_organizer then
    raise exception using errcode = '22023', message = 'lock fee split is invalid';
  end if;
  v_due_until := v_decided_at
    + pg_catalog.make_interval(hours => v_request.application_response_window_hours);

  update public.airfnb_applications
     set status = 'accepted', decided_at = v_decided_at
   where id = v_application.id;

  insert into public.airfnb_bookings(
    event_id, organizer_id, status, starts_at, ends_at, pax_count,
    total_amount, currency, notes, application_id
  ) values (
    null, v_request.organizer_id, 'pending_lock_fee', v_request.start_at,
    v_request.end_at, v_request.expected_pax, v_application.proposed_price,
    'EUR', v_request.notes, v_application.id
  ) returning id into v_booking_id;

  insert into public.airfnb_booking_trucks(booking_id, truck_id, agreed_price)
  values (v_booking_id, v_application.truck_id, v_application.proposed_price);

  insert into public.airfnb_lock_fees(
    application_id, amount, platform_fee, organizer_share,
    due_until, status, currency
  ) values (
    v_application.id, v_total, v_platform, v_organizer,
    v_due_until, 'pending', 'EUR'
  ) returning id into v_lock_fee_id;

  insert into public.airfnb_conversations(booking_id, application_id)
  values (v_booking_id, v_application.id)
  returning id into v_conversation_id;

  insert into public.airfnb_conversation_participants(conversation_id, user_id)
  select v_conversation_id, v_request.organizer_id
  union
  select v_conversation_id, truck.owner_id
    from public.airfnb_trucks as truck
   where truck.id = v_application.truck_id;

  insert into public.airfnb_notifications(user_id, kind, payload)
  select truck.owner_id,
         'application.accepted',
         pg_catalog.jsonb_build_object(
           'application_id', v_application.id,
           'request_id', v_request.id,
           'lock_fee_id', v_lock_fee_id,
           'total', v_total,
           'platform_fee', v_platform,
           'organizer_share', v_organizer,
           'deal_type', v_application.deal_type,
           'fixed_to_organizer', v_application.proposed_fixed_to_organizer,
           'revenue_share_pct', v_application.proposed_revenue_share_pct,
           'due_until', v_due_until
         )
    from public.airfnb_trucks as truck
   where truck.id = v_application.truck_id;

  v_accepted := v_accepted + 1;
  if v_accepted = v_request.slots_needed then
    update public.airfnb_event_requests
       set status = 'awarded', awarded_at = coalesce(awarded_at, v_decided_at)
     where id = v_request.id;
  end if;

  return pg_catalog.jsonb_build_object(
    'booking_id', v_booking_id,
    'lock_fee_id', v_lock_fee_id,
    'lock_fee', v_fee,
    'conversation_id', v_conversation_id
  );
end
$function$;

create or replace function public.airfnb_supplier_lock_fee(p_application uuid)
returns table (
  application_id uuid,
  application_status public.airfnb_application_status,
  proposed_price numeric,
  deal_type public.airfnb_deal_type,
  truck_id uuid,
  truck_name text,
  request_id uuid,
  request_title text,
  start_at timestamptz,
  city text,
  lock_fee_id uuid,
  amount numeric,
  platform_fee numeric,
  organizer_share numeric,
  currency char(3),
  due_until timestamptz,
  lock_fee_status public.airfnb_lock_fee_status
)
language sql
stable
security definer
set search_path = ''
as $function$
  select application.id,
         application.status,
         application.proposed_price,
         application.deal_type,
         truck.id,
         truck.name,
         request_row.id,
         request_row.title,
         request_row.start_at,
         request_row.city,
         lock_fee.id,
         lock_fee.amount,
         lock_fee.platform_fee,
         lock_fee.organizer_share,
         lock_fee.currency,
         lock_fee.due_until,
         lock_fee.status
    from public.airfnb_applications as application
    join public.airfnb_trucks as truck on truck.id = application.truck_id
    join public.airfnb_event_requests as request_row
      on request_row.id = application.request_id
    join public.airfnb_lock_fees as lock_fee
      on lock_fee.application_id = application.id
   where auth.uid() is not null
     and coalesce(
       pg_catalog.current_setting('request.jwt.claim.role', true), ''
     ) <> 'service_role'
     and truck.owner_id = auth.uid()
     and application.id = p_application
$function$;

revoke all on function public.airfnb_accept_application(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.airfnb_shortlist_application(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.airfnb_reject_application(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.airfnb_supplier_lock_fee(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.airfnb_own_application_truck()
  from public, anon, authenticated, service_role;
grant execute on function public.airfnb_accept_application(uuid)
  to authenticated, service_role;
grant execute on function public.airfnb_shortlist_application(uuid)
  to authenticated, service_role;
grant execute on function public.airfnb_reject_application(uuid, text)
  to authenticated, service_role;
grant execute on function public.airfnb_supplier_lock_fee(uuid)
  to authenticated;
grant execute on function public.airfnb_own_application_truck()
  to authenticated;

do $postconditions$
declare
  v_authenticated oid := (select oid from pg_catalog.pg_roles where rolname = 'authenticated');
  v_anon oid := (select oid from pg_catalog.pg_roles where rolname = 'anon');
  v_service_role oid := (select oid from pg_catalog.pg_roles where rolname = 'service_role');
begin
  if not exists (
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public' and tablename = 'airfnb_bookings'
       and indexname = 'airfnb_bookings_application_unique'
       and indexdef = 'CREATE UNIQUE INDEX airfnb_bookings_application_unique ON public.airfnb_bookings USING btree (application_id) WHERE (application_id IS NOT NULL)'
  ) then
    raise exception 'marketplace reconciliation failed: booking uniqueness postcondition';
  end if;

  if (select pg_catalog.array_agg(policy.polname order by policy.polname)
        from pg_catalog.pg_policy as policy
       where policy.polrelid = 'public.airfnb_applications'::pg_catalog.regclass)
       is distinct from array[
         'airfnb_app_insert_guarded','airfnb_app_select_participant'
       ]::name[] then
    raise exception 'marketplace reconciliation failed: application policy postcondition';
  end if;

  if not pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_applications', 'SELECT')
     or pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_applications', 'INSERT')
     or pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_applications', 'UPDATE')
     or pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_applications', 'DELETE')
     or not pg_catalog.has_column_privilege(v_authenticated, 'public.airfnb_applications', 'request_id', 'INSERT')
     or pg_catalog.has_column_privilege(v_authenticated, 'public.airfnb_applications', 'status', 'INSERT')
     or not pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_bookings', 'SELECT')
     or pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_bookings', 'INSERT')
     or not pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_booking_trucks', 'SELECT')
     or pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_booking_trucks', 'INSERT')
     or pg_catalog.has_table_privilege(v_authenticated, 'public.airfnb_lock_fees', 'SELECT')
     or not pg_catalog.has_table_privilege(v_service_role, 'public.airfnb_lock_fees', 'SELECT,INSERT,UPDATE,DELETE')
     or pg_catalog.has_table_privilege(v_anon, 'public.airfnb_applications', 'SELECT') then
    raise exception 'marketplace reconciliation failed: table ACL postcondition';
  end if;

  if exists (
    select 1
      from (values
        ('public.airfnb_accept_application(uuid)'::pg_catalog.regprocedure, array[v_authenticated,v_service_role]::oid[], array['search_path=pg_catalog, public']::text[]),
        ('public.airfnb_shortlist_application(uuid)'::pg_catalog.regprocedure, array[v_authenticated,v_service_role]::oid[], array['search_path=pg_catalog, public']::text[]),
        ('public.airfnb_reject_application(uuid,text)'::pg_catalog.regprocedure, array[v_authenticated,v_service_role]::oid[], array['search_path=pg_catalog, public']::text[]),
        ('public.airfnb_can_submit_application(uuid,uuid)'::pg_catalog.regprocedure, array[v_authenticated]::oid[], array['search_path=""']::text[]),
        ('public.airfnb_own_application_truck()'::pg_catalog.regprocedure, array[v_authenticated]::oid[], array['search_path=""']::text[]),
        ('public.airfnb_supplier_lock_fee(uuid)'::pg_catalog.regprocedure, array[v_authenticated]::oid[], array['search_path=""']::text[])
      ) as expected(function_oid, grantees, config)
      join pg_catalog.pg_proc as procedure on procedure.oid = expected.function_oid
     where not procedure.prosecdef
        or procedure.proowner <> (
          select relowner from pg_catalog.pg_class
           where oid = 'public.airfnb_applications'::pg_catalog.regclass
        )
        or procedure.proconfig is distinct from expected.config
        or exists (
          select 1
            from pg_catalog.aclexplode(
              coalesce(procedure.proacl, pg_catalog.acldefault('f', procedure.proowner))
            ) as privilege
           where privilege.privilege_type = 'EXECUTE'
             and privilege.grantee <> procedure.proowner
             and not privilege.grantee = any(expected.grantees)
        )
        or exists (
          select 1 from unnest(expected.grantees) as grantee(oid)
           where not pg_catalog.has_function_privilege(grantee.oid, procedure.oid, 'EXECUTE')
        )
  ) or pg_catalog.has_function_privilege(v_anon, 'public.airfnb_accept_application(uuid)', 'EXECUTE')
     or pg_catalog.has_function_privilege(v_service_role, 'public.airfnb_supplier_lock_fee(uuid)', 'EXECUTE') then
    raise exception 'marketplace reconciliation failed: RPC owner, path or ACL postcondition';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc as procedure
     where procedure.oid = 'public.airfnb_can_submit_application(uuid,uuid)'::pg_catalog.regprocedure
       and procedure.proowner = (
         select relowner from pg_catalog.pg_class
          where oid = 'public.airfnb_applications'::pg_catalog.regclass
       )
       and procedure.prosecdef
       and procedure.provolatile = 's'
       and procedure.proconfig = array['search_path=""']::text[]
       and procedure.prorettype = 'boolean'::pg_catalog.regtype
       and pg_catalog.md5(procedure.prosrc) = 'c96f49df5f1b05fabea73bfdbf534a74'
       and pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
       and not pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
       and not pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
  ) then
    raise exception 'marketplace reconciliation failed: application submission helper postcondition';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc as procedure
     where procedure.oid = 'public.airfnb_own_application_truck()'::pg_catalog.regprocedure
       and procedure.proowner = (
         select relowner from pg_catalog.pg_class
          where oid = 'public.airfnb_applications'::pg_catalog.regclass
       )
       and procedure.prosecdef
       and procedure.provolatile = 's'
       and procedure.proconfig = array['search_path=""']::text[]
       and procedure.proretset
       and procedure.proallargtypes = array[
         'uuid'::pg_catalog.regtype,
         'text'::pg_catalog.regtype,
         'public.airfnb_truck_status'::pg_catalog.regtype
       ]::oid[]
       and procedure.proargmodes = array['t','t','t']::"char"[]
       and procedure.proargnames = array[
         'truck_id','truck_name','truck_status'
       ]::text[]
       and pg_catalog.md5(procedure.prosrc) = 'f8b910f51897ceb6b4fea4e1b049d02b'
       and pg_catalog.has_function_privilege(v_authenticated, procedure.oid, 'EXECUTE')
       and not pg_catalog.has_function_privilege(v_anon, procedure.oid, 'EXECUTE')
       and not pg_catalog.has_function_privilege(v_service_role, procedure.oid, 'EXECUTE')
  ) then
    raise exception 'marketplace reconciliation failed: own application truck helper postcondition';
  end if;

  if exists (
    select 1
      from airfnb_marketplace_protected_functions_20260820 as original
      join pg_catalog.pg_proc as procedure on procedure.oid = original.oid
     where procedure.proowner <> original.proowner
        or procedure.proacl is distinct from original.proacl
        or procedure.prosecdef <> original.prosecdef
        or procedure.provolatile <> original.provolatile
        or procedure.proconfig is distinct from original.proconfig
        or pg_catalog.md5(procedure.prosrc) <> original.body_hash
  ) or exists (
    select 1
      from airfnb_marketplace_protected_relations_20260820 as original
      join pg_catalog.pg_class as relation on relation.oid = original.oid
     where relation.relowner <> original.relowner
        or relation.relacl is distinct from original.relacl
        or relation.relrowsecurity <> original.relrowsecurity
        or relation.relforcerowsecurity <> original.relforcerowsecurity
  ) or exists (
    (select oid, polrelid, polname, polcmd, polpermissive, polroles,
            using_expression, check_expression
       from airfnb_marketplace_protected_policies_20260820)
    except
    (select policy.oid, policy.polrelid, policy.polname, policy.polcmd,
            policy.polpermissive, policy.polroles,
            pg_catalog.pg_get_expr(policy.polqual, policy.polrelid),
            pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
       from pg_catalog.pg_policy as policy
      where policy.polrelid in (
        select polrelid from airfnb_marketplace_protected_policies_20260820
      ))
  ) or exists (
    (select policy.oid, policy.polrelid, policy.polname, policy.polcmd,
            policy.polpermissive, policy.polroles,
            pg_catalog.pg_get_expr(policy.polqual, policy.polrelid),
            pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
       from pg_catalog.pg_policy as policy
      where policy.polrelid in (
        select polrelid from airfnb_marketplace_protected_policies_20260820
      ))
    except
    (select oid, polrelid, polname, polcmd, polpermissive, polroles,
            using_expression, check_expression
       from airfnb_marketplace_protected_policies_20260820)
  ) then
    raise exception 'marketplace reconciliation failed: predecessor contract changed';
  end if;
end
$postconditions$;

commit;
