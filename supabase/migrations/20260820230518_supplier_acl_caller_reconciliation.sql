-- Post-Stripe reconciliation for the catalog ACL callers that legitimately
-- need owner-, participant- or public-scoped projections.  The catalog base
-- tables remain least-privilege: in particular owner_id is never selectable
-- by an API role.

begin;

do $preconditions$
declare
  v_role name;
  v_stripe record;
  v_manage record;
  v_review_policy record;
begin
  if to_regprocedure('public.airfnb_reconcile_stripe_event(text,text,timestamptz,uuid,uuid,uuid,text,bigint,text,text,bigint)') is null then
    raise exception 'supplier ACL reconciliation refused: Stripe predecessor is missing';
  end if;

  select p.proowner, p.prosecdef, p.provolatile, p.proconfig,
         pg_catalog.md5(p.prosrc) as body_hash
    into v_stripe
    from pg_catalog.pg_proc as p
   where p.oid = 'public.airfnb_reconcile_stripe_event(text,text,timestamptz,uuid,uuid,uuid,text,bigint,text,text,bigint)'::regprocedure;

  if v_stripe.body_hash <> '296b93ed41a788acf9ecb099e78695ff'
     or not v_stripe.prosecdef
     or v_stripe.provolatile <> 'v'
     or v_stripe.proconfig is distinct from array['search_path=""']::text[]
     or v_stripe.proowner <> (
       select c.relowner from pg_catalog.pg_class as c
        where c.oid = 'public.airfnb_stripe_events'::regclass
     ) then
    raise exception 'supplier ACL reconciliation refused: Stripe predecessor drifted';
  end if;

  if to_regprocedure('public.airfnb_can_submit_application(uuid,uuid)') is null
     or to_regprocedure('public.airfnb_supplier_lock_fee(uuid)') is null
     or to_regclass('public.airfnb_v_truck_card') is null then
    raise exception 'supplier ACL reconciliation refused: marketplace/catalog predecessor is missing';
  end if;

  select p.proowner, p.prosecdef, p.provolatile, p.proconfig,
         pg_catalog.md5(p.prosrc) as body_hash
    into v_manage
    from pg_catalog.pg_proc as p
   where p.oid = 'public.airfnb_can_manage_truck(text)'::regprocedure;
  if v_manage.body_hash <> '982caee25d35d0ac9dfe1d3a343ab0a5'
     or not v_manage.prosecdef
     or v_manage.provolatile <> 's'
     or v_manage.proconfig is distinct from array['search_path=""']::text[]
     or v_manage.proowner <> (
       select c.relowner from pg_catalog.pg_class as c
        where c.oid = 'public.airfnb_trucks'::regclass
     ) then
    raise exception 'supplier ACL reconciliation refused: ownership helper drifted';
  end if;

  select policy.polcmd, policy.polpermissive, policy.polroles,
         policy.polqual,
         pg_catalog.md5(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)) as body_hash
    into v_review_policy
    from pg_catalog.pg_policy as policy
   where policy.polrelid = 'public.airfnb_organizer_reviews'::regclass
     and policy.polname = 'airfnb_org_reviews_participant_insert';
  if v_review_policy.polcmd is distinct from 'a'::"char"
     or v_review_policy.polpermissive is distinct from true
     or v_review_policy.polroles is distinct from array['authenticated'::regrole::oid]
     or v_review_policy.polqual is not null
     or v_review_policy.body_hash not in (
       'eb6ed73b9db344da97e1be5244cefd54',
       '64f6778971e136463d322c17b734dc76'
     ) then
    raise exception 'supplier ACL reconciliation refused: organizer review policy drifted';
  end if;

  foreach v_role in array array['anon'::name, 'authenticated'::name, 'service_role'::name]
  loop
    if pg_catalog.has_table_privilege(v_role, 'public.airfnb_trucks', 'SELECT')
       or pg_catalog.has_table_privilege(v_role, 'public.airfnb_truck_images', 'SELECT')
       or pg_catalog.has_table_privilege(v_role, 'public.airfnb_truck_categories', 'SELECT')
       or pg_catalog.has_table_privilege(v_role, 'public.airfnb_categories', 'SELECT') then
      raise exception 'supplier ACL reconciliation refused: broad catalog SELECT exists for %', v_role;
    end if;

    if pg_catalog.has_column_privilege(
         v_role, 'public.airfnb_trucks', 'owner_id', 'SELECT'
       ) then
      raise exception 'supplier ACL reconciliation refused: owner_id is selectable by %', v_role;
    end if;
  end loop;
end
$preconditions$;

-- The verified Messaging policy compared owner_id under the caller's table
-- privileges. Once Catalog correctly closed owner_id, that safe insert path
-- became unusable. Rebind only the ownership predicate to the already pinned
-- owner-scoped SECURITY DEFINER helper; all review/booking checks remain in
-- the verified trigger and every remaining WITH CHECK term is unchanged.
alter policy airfnb_org_reviews_participant_insert
  on public.airfnb_organizer_reviews
  to authenticated
  with check (
    is_verified is true
    and rating_reliability between 1 and 5
    and rating_communication between 1 and 5
    and rating_payment between 1 and 5
    and rating_overall = round(
      (rating_reliability + rating_communication + rating_payment)::numeric / 3,
      1
    )
    and reply_body is null
    and reply_at is null
    and public.airfnb_can_manage_truck(truck_id::text)
  );

-- Public taxonomy labels are not supplier/private data.  Image ids are needed
-- only by authenticated owner mutation flows; row visibility remains governed
-- by the verified child-table RLS policy.
grant select (name_pt, name_en, icon)
  on table public.airfnb_categories
  to anon, authenticated, service_role;

grant select (id)
  on table public.airfnb_truck_images
  to authenticated;

create or replace function public.airfnb_supplier_services(
  p_truck uuid default null
)
returns table (
  id uuid,
  slug text,
  name text,
  tagline text,
  description text,
  base_city text,
  service_radius_km integer,
  capacity integer,
  min_event_pax integer,
  max_event_pax integer,
  base_price numeric,
  price_per_pax numeric,
  setup_minutes integer,
  power_required_kw numeric,
  needs_water boolean,
  dimensions_m numeric[],
  status public.airfnb_truck_status,
  rating_avg numeric,
  rating_count integer,
  featured boolean,
  homologation_expires_at date,
  insurance_expires_at date,
  created_at timestamptz,
  updated_at timestamptz,
  lead_response_rate numeric,
  last_active_at timestamptz,
  subscription_tier text,
  cuisine_types text[],
  dietary_options public.airfnb_dietary_tag[],
  teardown_minutes integer,
  sanitation_required text,
  catering_type text,
  serves text,
  compatible_event_kinds public.airfnb_event_kind[],
  service_type public.airfnb_service_type
)
language sql
stable
security definer
set search_path = ''
as $function$
  select truck.id,
         truck.slug,
         truck.name,
         truck.tagline,
         truck.description,
         truck.base_city,
         truck.service_radius_km,
         truck.capacity,
         truck.min_event_pax,
         truck.max_event_pax,
         truck.base_price,
         truck.price_per_pax,
         truck.setup_minutes,
         truck.power_required_kw,
         truck.needs_water,
         truck.dimensions_m,
         truck.status,
         truck.rating_avg,
         truck.rating_count,
         truck.featured,
         truck.homologation_expires_at,
         truck.insurance_expires_at,
         truck.created_at,
         truck.updated_at,
         truck.lead_response_rate,
         truck.last_active_at,
         truck.subscription_tier,
         truck.cuisine_types,
         truck.dietary_options,
         truck.teardown_minutes,
         truck.sanitation_required,
         truck.catering_type,
         truck.serves,
         truck.compatible_event_kinds,
         truck.service_type
    from public.airfnb_trucks as truck
   where auth.uid() is not null
     and coalesce(pg_catalog.current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     and truck.owner_id = auth.uid()
     and (p_truck is null or truck.id = p_truck)
   order by truck.created_at, truck.id
$function$;

create or replace function public.airfnb_public_service_detail(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_payload jsonb;
  v_slug text := pg_catalog.btrim(coalesce(p_slug, ''));
begin
  if v_slug = '' or pg_catalog.length(v_slug) > 200 then
    return null;
  end if;

  select pg_catalog.jsonb_build_object(
           'id', truck.id,
           'slug', truck.slug,
           'name', truck.name,
           'tagline', truck.tagline,
           'description', truck.description,
           'base_city', truck.base_city,
           'service_radius_km', truck.service_radius_km,
           'capacity', truck.capacity,
           'min_event_pax', truck.min_event_pax,
           'max_event_pax', truck.max_event_pax,
           'base_price', truck.base_price,
           'price_per_pax', truck.price_per_pax,
           'setup_minutes', truck.setup_minutes,
           'teardown_minutes', truck.teardown_minutes,
           'power_required_kw', truck.power_required_kw,
           'needs_water', truck.needs_water,
           'dimensions_m', truck.dimensions_m,
           'sanitation_required', truck.sanitation_required,
           'catering_type', truck.catering_type,
           'serves', truck.serves,
           'cuisine_types', truck.cuisine_types,
           'dietary_options', truck.dietary_options,
           'compatible_event_kinds', truck.compatible_event_kinds,
           'service_type', truck.service_type,
           'status', truck.status,
           'rating_avg', truck.rating_avg,
           'rating_count', truck.rating_count,
           'lead_response_rate', truck.lead_response_rate,
           'homologation_state', case
             when truck.homologation_expires_at is null then 'unknown'
             when truck.homologation_expires_at < current_date then 'expired'
             when truck.homologation_expires_at <= current_date + 30 then 'expiring'
             else 'valid'
           end,
           'insurance_state', case
             when truck.insurance_expires_at is null then 'unknown'
             when truck.insurance_expires_at < current_date then 'expired'
             when truck.insurance_expires_at <= current_date + 30 then 'expiring'
             else 'valid'
           end,
           'owner', pg_catalog.jsonb_build_object(
             'display_name', profile.display_name,
             'avatar_url', profile.avatar_url,
             'member_since_year', extract(year from profile.created_at)::integer
           ),
           'images', coalesce((
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'id', image_row.id,
                        'url', image_row.url,
                        'alt', image_row.alt,
                        'is_cover', image_row.is_cover,
                        'sort_order', image_row.sort_order,
                        'kind', image_row.kind
                      ) order by image_row.kind_rank,
                                 image_row.is_cover_rank,
                                 image_row.sort_order,
                                 image_row.id
                    )
               from (
                 select image.id,
                        image.url,
                        image.alt,
                        image.is_cover,
                        image.sort_order,
                        image.kind,
                        case image.kind
                          when 'truck' then 1 when 'food' then 2
                          when 'venue' then 3 when 'team' then 4 else 5
                        end as kind_rank,
                        case when image.is_cover then 0 else 1 end as is_cover_rank
                   from public.airfnb_truck_images as image
                  where image.truck_id = truck.id
                  order by kind_rank, is_cover_rank, image.sort_order, image.id
                  limit 12
               ) as image_row
           ), '[]'::jsonb),
           'menu_items', coalesce((
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'id', menu_row.id,
                        'name', menu_row.name,
                        'description', menu_row.description,
                        'price', menu_row.price,
                        'category', menu_row.category
                      ) order by menu_row.sort_order, menu_row.id
                    )
               from (
                 select menu.id, menu.name, menu.description, menu.price,
                        menu.category, menu.sort_order
                   from public.airfnb_menu_items as menu
                  where menu.truck_id = truck.id
                  order by menu.sort_order, menu.id
                  limit 100
               ) as menu_row
           ), '[]'::jsonb),
           'categories', coalesce((
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'slug', category_row.slug,
                        'name_pt', category_row.name_pt,
                        'icon', category_row.icon
                      ) order by category_row.slug
                    )
               from (
                 select category.slug, category.name_pt, category.icon
                   from public.airfnb_truck_categories as truck_category
                   join public.airfnb_categories as category
                     on category.id = truck_category.category_id
                  where truck_category.truck_id = truck.id
                  order by category.slug
                  limit 50
               ) as category_row
           ), '[]'::jsonb),
           'document_states', coalesce((
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'kind', document_row.kind,
                        'state', document_row.state
                      ) order by document_row.kind
                    )
               from (
                 select document.kind,
                        case
                          when document.expires_at is null then 'unknown'
                          when document.expires_at < current_date then 'expired'
                          when document.expires_at <= current_date + 30 then 'expiring'
                          else 'valid'
                        end as state
                   from public.airfnb_truck_documents as document
                  where document.truck_id = truck.id
                  order by document.kind, document.id
                  limit 8
               ) as document_row
           ), '[]'::jsonb)
         )
    into v_payload
    from public.airfnb_trucks as truck
    join public.airfnb_profiles as profile on profile.id = truck.owner_id
   where truck.slug = v_slug
     and truck.status = 'active'::public.airfnb_truck_status;

  return v_payload;
end
$function$;

create or replace function public.airfnb_invitation_candidates(p_request uuid)
returns table (
  truck_id uuid,
  slug text,
  name text,
  base_city text,
  cover_url text,
  capacity integer,
  rating_avg numeric,
  rating_count integer,
  cuisine_types text[],
  category_slugs text[],
  already_invited boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null
     or coalesce(pg_catalog.current_setting('request.jwt.claim.role', true), '') = 'service_role' then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;

  return query
  with request_row as (
    select request.id,
           coalesce(nullif(pg_catalog.btrim(request.city), ''),
                    nullif(pg_catalog.btrim(request.locality), '')) as wanted_city,
           request.expected_pax,
           request.desired_cuisines
      from public.airfnb_event_requests as request
     where request.id = p_request
       and request.organizer_id = auth.uid()
       and request.status in (
         'open'::public.airfnb_request_status,
         'reviewing'::public.airfnb_request_status
       )
  )
  select truck.id,
         truck.slug,
         truck.name,
         truck.base_city,
         (
           select image.url
             from public.airfnb_truck_images as image
            where image.truck_id = truck.id
            order by case image.kind
                       when 'truck' then 1 when 'food' then 2
                       when 'venue' then 3 when 'team' then 4 else 5
                     end,
                     case when image.is_cover then 0 else 1 end,
                     image.sort_order,
                     image.id
            limit 1
         ),
         truck.capacity,
         truck.rating_avg,
         truck.rating_count,
         truck.cuisine_types,
         array(
           select category.slug
             from public.airfnb_truck_categories as truck_category
             join public.airfnb_categories as category
               on category.id = truck_category.category_id
            where truck_category.truck_id = truck.id
            order by category.slug
         ),
         exists (
           select 1
             from public.airfnb_request_invitations as invitation
            where invitation.request_id = request_row.id
              and invitation.truck_id = truck.id
         )
    from request_row
    join public.airfnb_trucks as truck
      on truck.status = 'active'::public.airfnb_truck_status
   where (
       request_row.wanted_city is null
       or pg_catalog.strpos(
            pg_catalog.lower(coalesce(truck.base_city, '')),
            pg_catalog.lower(request_row.wanted_city)
          ) > 0
     )
     and (request_row.expected_pax is null or truck.capacity >= request_row.expected_pax)
     and (
       coalesce(pg_catalog.cardinality(request_row.desired_cuisines), 0) = 0
       or truck.cuisine_types && request_row.desired_cuisines
     )
   order by truck.rating_avg desc nulls last, truck.id
   limit 80;
end
$function$;

create or replace function public.airfnb_invite_request_services(
  p_request uuid,
  p_trucks uuid[]
)
returns table (truck_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_request_owner uuid;
  v_request_status public.airfnb_request_status;
  v_request_title text;
  v_request_city text;
  v_request_locality text;
  v_request_expected_pax integer;
  v_request_desired_cuisines text[];
  v_trucks uuid[];
  v_city text;
  v_expected integer;
  v_inserted uuid;
begin
  if v_uid is null
     or coalesce(pg_catalog.current_setting('request.jwt.claim.role', true), '') = 'service_role' then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;

  if p_request is null then
    raise exception using errcode = '22023', message = 'request is required';
  end if;

  select pg_catalog.array_agg(input.truck_id order by input.truck_id)
    into v_trucks
    from (
      select distinct item as truck_id
        from pg_catalog.unnest(coalesce(p_trucks, array[]::uuid[])) as item
       where item is not null
    ) as input;

  if coalesce(pg_catalog.cardinality(v_trucks), 0) = 0 then
    raise exception using errcode = '22023', message = 'at least one service is required';
  end if;
  if pg_catalog.cardinality(v_trucks) > 80 then
    raise exception using errcode = '22023', message = 'too many services';
  end if;

  select request.organizer_id, request.status, request.title,
         request.city, request.locality, request.expected_pax,
         request.desired_cuisines
    into v_request_owner, v_request_status, v_request_title,
         v_request_city, v_request_locality, v_request_expected_pax,
         v_request_desired_cuisines
    from public.airfnb_event_requests as request
   where request.id = p_request
   for update;

  if not found or v_request_owner <> v_uid then
    raise exception using errcode = '42501', message = 'request is not manageable';
  end if;
  if v_request_status not in (
       'open'::public.airfnb_request_status,
       'reviewing'::public.airfnb_request_status
     ) then
    raise exception using errcode = '22023', message = 'request is not open for invitations';
  end if;

  -- Consistent lock ordering prevents a status edit from racing eligibility
  -- and prevents two multi-service invitation calls from deadlocking.
  perform 1
    from public.airfnb_trucks as truck
   where truck.id = any(v_trucks)
   order by truck.id
   for share;

  v_city := coalesce(nullif(pg_catalog.btrim(v_request_city), ''),
                     nullif(pg_catalog.btrim(v_request_locality), ''));

  select pg_catalog.count(*)::integer
    into v_expected
    from public.airfnb_trucks as truck
   where truck.id = any(v_trucks)
     and truck.status = 'active'::public.airfnb_truck_status
     and (
       v_city is null
       or pg_catalog.strpos(
            pg_catalog.lower(coalesce(truck.base_city, '')),
            pg_catalog.lower(v_city)
          ) > 0
     )
     and (v_request_expected_pax is null or truck.capacity >= v_request_expected_pax)
     and (
       coalesce(pg_catalog.cardinality(v_request_desired_cuisines), 0) = 0
       or truck.cuisine_types && v_request_desired_cuisines
     );

  if v_expected <> pg_catalog.cardinality(v_trucks) then
    raise exception using errcode = '22023', message = 'one or more services are not eligible';
  end if;

  for v_inserted in
    insert into public.airfnb_request_invitations(request_id, truck_id, invited_by)
    select p_request, input.truck_id, v_uid
      from pg_catalog.unnest(v_trucks) as input(truck_id)
     order by input.truck_id
    on conflict on constraint airfnb_request_invitations_pkey do nothing
    returning airfnb_request_invitations.truck_id
  loop
    insert into public.airfnb_notifications(user_id, kind, payload)
    select truck.owner_id,
           'request.invited',
           pg_catalog.jsonb_build_object(
             'request_id', p_request,
             'request_title', v_request_title,
             'truck_id', truck.id,
             'truck_name', truck.name
           )
      from public.airfnb_trucks as truck
     where truck.id = v_inserted;

    truck_id := v_inserted;
    return next;
  end loop;
end
$function$;

create or replace function public.airfnb_booking_service_context(
  p_booking uuid default null
)
returns table (
  booking_id uuid,
  booking_status public.airfnb_booking_status,
  starts_at timestamptz,
  ends_at timestamptz,
  pax_count integer,
  total_amount numeric,
  currency character(3),
  ics_token text,
  application_id uuid,
  request_id uuid,
  request_title text,
  request_city text,
  event_title text,
  organizer_display_name text,
  truck_id uuid,
  truck_name text,
  truck_slug text,
  truck_base_city text,
  agreed_price numeric,
  is_organizer boolean,
  is_owned boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null
     or coalesce(pg_catalog.current_setting('request.jwt.claim.role', true), '') = 'service_role' then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;

  return query
  select booking.id,
         booking.status,
         booking.starts_at,
         booking.ends_at,
         booking.pax_count,
         booking.total_amount,
         booking.currency,
         booking.ics_token,
         booking.application_id,
         request.id,
         request.title,
         request.city,
         event_row.title,
         organizer.display_name,
         truck.id,
         truck.name,
         truck.slug,
         truck.base_city,
         booking_truck.agreed_price,
         booking.organizer_id = auth.uid(),
         truck.owner_id = auth.uid()
    from public.airfnb_bookings as booking
    join public.airfnb_booking_trucks as booking_truck
      on booking_truck.booking_id = booking.id
    join public.airfnb_trucks as truck on truck.id = booking_truck.truck_id
    left join public.airfnb_applications as application
      on application.id = booking.application_id
    left join public.airfnb_event_requests as request
      on request.id = application.request_id
    left join public.airfnb_events as event_row on event_row.id = booking.event_id
    left join public.airfnb_profiles as organizer on organizer.id = booking.organizer_id
   where (p_booking is null or booking.id = p_booking)
     and (
       booking.organizer_id = auth.uid()
       or truck.owner_id = auth.uid()
     )
   order by booking.starts_at, booking.id, truck.id;
end
$function$;

create or replace function public.airfnb_request_application_service_context(
  p_request uuid
)
returns table (
  application_id uuid,
  application_status public.airfnb_application_status,
  proposed_price numeric,
  cover_message text,
  deal_type public.airfnb_deal_type,
  proposed_fixed_to_organizer numeric,
  proposed_revenue_share_pct numeric,
  created_at timestamptz,
  truck_id uuid,
  truck_name text,
  truck_slug text,
  truck_base_city text,
  truck_rating_avg numeric,
  truck_rating_count integer
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null
     or coalesce(pg_catalog.current_setting('request.jwt.claim.role', true), '') = 'service_role' then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;

  return query
  select application.id,
         application.status,
         application.proposed_price,
         application.cover_message,
         application.deal_type,
         application.proposed_fixed_to_organizer,
         application.proposed_revenue_share_pct,
         application.created_at,
         truck.id,
         truck.name,
         truck.slug,
         truck.base_city,
         truck.rating_avg,
         truck.rating_count
    from public.airfnb_event_requests as request
    join public.airfnb_applications as application
      on application.request_id = request.id
    join public.airfnb_trucks as truck on truck.id = application.truck_id
   where request.id = p_request
     and (
       request.organizer_id = auth.uid()
       or public.airfnb_is_admin()
     )
   order by application.created_at desc, application.id;
end
$function$;

create or replace function public.airfnb_supplier_export_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_payload jsonb;
begin
  if auth.uid() is null
     or coalesce(pg_catalog.current_setting('request.jwt.claim.role', true), '') = 'service_role' then
    raise exception using errcode = '42501', message = 'authentication required';
  end if;

  select pg_catalog.jsonb_build_object(
           'trucks_as_owner', coalesce((
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'id', service.id,
                        'slug', service.slug,
                        'name', service.name,
                        'tagline', service.tagline,
                        'description', service.description,
                        'base_city', service.base_city,
                        'service_radius_km', service.service_radius_km,
                        'capacity', service.capacity,
                        'min_event_pax', service.min_event_pax,
                        'max_event_pax', service.max_event_pax,
                        'base_price', service.base_price,
                        'price_per_pax', service.price_per_pax,
                        'setup_minutes', service.setup_minutes,
                        'teardown_minutes', service.teardown_minutes,
                        'power_required_kw', service.power_required_kw,
                        'needs_water', service.needs_water,
                        'dimensions_m', service.dimensions_m,
                        'sanitation_required', service.sanitation_required,
                        'catering_type', service.catering_type,
                        'serves', service.serves,
                        'cuisine_types', service.cuisine_types,
                        'dietary_options', service.dietary_options,
                        'compatible_event_kinds', service.compatible_event_kinds,
                        'service_type', service.service_type,
                        'status', service.status,
                        'rating_avg', service.rating_avg,
                        'rating_count', service.rating_count,
                        'featured', service.featured,
                        'homologation_expires_at', service.homologation_expires_at,
                        'insurance_expires_at', service.insurance_expires_at,
                        'lead_response_rate', service.lead_response_rate,
                        'last_active_at', service.last_active_at,
                        'subscription_tier', service.subscription_tier,
                        'created_at', service.created_at,
                        'updated_at', service.updated_at
                      ) order by service.created_at, service.id
                    )
               from (
                 select service_row.id, service_row.slug, service_row.name,
                        service_row.tagline, service_row.description,
                        service_row.base_city, service_row.service_radius_km,
                        service_row.capacity, service_row.min_event_pax,
                        service_row.max_event_pax, service_row.base_price,
                        service_row.price_per_pax, service_row.setup_minutes,
                        service_row.power_required_kw, service_row.needs_water,
                        service_row.dimensions_m, service_row.status,
                        service_row.rating_avg, service_row.rating_count,
                        service_row.featured,
                        service_row.homologation_expires_at,
                        service_row.insurance_expires_at,
                        service_row.created_at, service_row.updated_at,
                        service_row.lead_response_rate,
                        service_row.last_active_at,
                        service_row.subscription_tier,
                        service_row.cuisine_types,
                        service_row.dietary_options,
                        service_row.teardown_minutes,
                        service_row.sanitation_required,
                        service_row.catering_type, service_row.serves,
                        service_row.compatible_event_kinds,
                        service_row.service_type
                   from public.airfnb_supplier_services(null) as service_row
                  limit 10000
               ) as service
           ), '[]'::jsonb),
           'applications_as_owner', coalesce((
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'id', application.id,
                        'request_id', application.request_id,
                        'truck_id', application.truck_id,
                        'proposed_price', application.proposed_price,
                        'cover_message', application.cover_message,
                        'menu_pitch', application.menu_pitch,
                        'estimated_servings', application.estimated_servings,
                        'available_confirmed', application.available_confirmed,
                        'status', application.status,
                        'deal_type', application.deal_type,
                        'proposed_fixed_to_organizer', application.proposed_fixed_to_organizer,
                        'proposed_revenue_share_pct', application.proposed_revenue_share_pct,
                        'shortlisted_at', application.shortlisted_at,
                        'decided_at', application.decided_at,
                        'withdrawn_at', application.withdrawn_at,
                        'created_at', application.created_at,
                        'updated_at', application.updated_at
                      ) order by application.created_at, application.id
                    )
               from (
                 select app.id, app.request_id, app.truck_id,
                        app.proposed_price, app.cover_message, app.menu_pitch,
                        app.estimated_servings, app.available_confirmed,
                        app.status, app.deal_type,
                        app.proposed_fixed_to_organizer,
                        app.proposed_revenue_share_pct,
                        app.shortlisted_at, app.decided_at, app.withdrawn_at,
                        app.created_at, app.updated_at
                   from public.airfnb_applications as app
                   join public.airfnb_trucks as truck on truck.id = app.truck_id
                  where truck.owner_id = auth.uid()
                  order by app.created_at, app.id
                  limit 10000
               ) as application
           ), '[]'::jsonb),
           'reviews_left_for_organizers', coalesce((
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'id', review.id,
                        'booking_id', review.booking_id,
                        'truck_id', review.truck_id,
                        'organizer_id', review.organizer_id,
                        'rating_reliability', review.rating_reliability,
                        'rating_communication', review.rating_communication,
                        'rating_payment', review.rating_payment,
                        'rating_overall', review.rating_overall,
                        'body', review.body,
                        'created_at', review.created_at
                      ) order by review.created_at, review.id
                    )
               from (
                 select organizer_review.id, organizer_review.booking_id,
                        organizer_review.truck_id, organizer_review.organizer_id,
                        organizer_review.rating_reliability,
                        organizer_review.rating_communication,
                        organizer_review.rating_payment,
                        organizer_review.rating_overall,
                        organizer_review.body, organizer_review.created_at
                   from public.airfnb_organizer_reviews as organizer_review
                   join public.airfnb_trucks as truck
                     on truck.id = organizer_review.truck_id
                  where truck.owner_id = auth.uid()
                  order by organizer_review.created_at, organizer_review.id
                  limit 10000
               ) as review
           ), '[]'::jsonb),
           'lock_fees', coalesce((
             select pg_catalog.jsonb_agg(
                      pg_catalog.jsonb_build_object(
                        'id', lock_fee.id,
                        'application_id', lock_fee.application_id,
                        'amount', lock_fee.amount,
                        'platform_fee', lock_fee.platform_fee,
                        'organizer_share', lock_fee.organizer_share,
                        'currency', lock_fee.currency,
                        'due_until', lock_fee.due_until,
                        'status', lock_fee.status,
                        'paid_at', lock_fee.paid_at,
                        'provider_ref', lock_fee.provider_ref,
                        'refunded_at', lock_fee.refunded_at,
                        'created_at', lock_fee.created_at
                      ) order by lock_fee.created_at, lock_fee.id
                    )
               from (
                 select fee.id, fee.application_id, fee.amount,
                        fee.platform_fee, fee.organizer_share, fee.currency,
                        fee.due_until, fee.status, fee.paid_at,
                        fee.provider_ref, fee.refunded_at, fee.created_at
                   from public.airfnb_lock_fees as fee
                   join public.airfnb_applications as application
                     on application.id = fee.application_id
                   join public.airfnb_trucks as truck
                     on truck.id = application.truck_id
                  where truck.owner_id = auth.uid()
                  order by fee.created_at, fee.id
                  limit 10000
               ) as lock_fee
           ), '[]'::jsonb)
         )
    into v_payload;

  return v_payload;
end
$function$;

revoke all on function public.airfnb_supplier_services(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.airfnb_public_service_detail(text)
  from public, anon, authenticated, service_role;
revoke all on function public.airfnb_invitation_candidates(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.airfnb_invite_request_services(uuid, uuid[])
  from public, anon, authenticated, service_role;
revoke all on function public.airfnb_booking_service_context(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.airfnb_request_application_service_context(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.airfnb_supplier_export_data()
  from public, anon, authenticated, service_role;

grant execute on function public.airfnb_public_service_detail(text)
  to anon, authenticated;
grant execute on function public.airfnb_supplier_services(uuid)
  to authenticated;
grant execute on function public.airfnb_invitation_candidates(uuid)
  to authenticated;
grant execute on function public.airfnb_invite_request_services(uuid, uuid[])
  to authenticated;
grant execute on function public.airfnb_booking_service_context(uuid)
  to authenticated;
grant execute on function public.airfnb_request_application_service_context(uuid)
  to authenticated;
grant execute on function public.airfnb_supplier_export_data()
  to authenticated;

do $postconditions$
declare
  v_role name;
  v_owner oid := (
    select c.relowner from pg_catalog.pg_class as c
     where c.oid = 'public.airfnb_trucks'::regclass
  );
  v_function record;
begin
  foreach v_role in array array['anon'::name, 'authenticated'::name, 'service_role'::name]
  loop
    if pg_catalog.has_table_privilege(v_role, 'public.airfnb_trucks', 'SELECT')
       or pg_catalog.has_table_privilege(v_role, 'public.airfnb_truck_images', 'SELECT')
       or pg_catalog.has_table_privilege(v_role, 'public.airfnb_truck_categories', 'SELECT')
       or pg_catalog.has_table_privilege(v_role, 'public.airfnb_categories', 'SELECT')
       or pg_catalog.has_column_privilege(v_role, 'public.airfnb_trucks', 'owner_id', 'SELECT') then
      raise exception 'supplier ACL reconciliation failed: broad/owner ACL for %', v_role;
    end if;
  end loop;

  foreach v_role in array array['anon'::name, 'authenticated'::name, 'service_role'::name]
  loop
    if not pg_catalog.has_column_privilege(v_role, 'public.airfnb_categories', 'name_pt', 'SELECT')
       or not pg_catalog.has_column_privilege(v_role, 'public.airfnb_categories', 'name_en', 'SELECT')
       or not pg_catalog.has_column_privilege(v_role, 'public.airfnb_categories', 'icon', 'SELECT') then
      raise exception 'supplier ACL reconciliation failed: category projection ACL for %', v_role;
    end if;
  end loop;

  if not pg_catalog.has_column_privilege('authenticated', 'public.airfnb_truck_images', 'id', 'SELECT')
     or pg_catalog.has_column_privilege('anon', 'public.airfnb_truck_images', 'id', 'SELECT')
     or pg_catalog.has_column_privilege('service_role', 'public.airfnb_truck_images', 'id', 'SELECT') then
    raise exception 'supplier ACL reconciliation failed: image id ACL';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_policy as policy
     where policy.polrelid = 'public.airfnb_organizer_reviews'::regclass
       and policy.polname = 'airfnb_org_reviews_participant_insert'
       and policy.polcmd = 'a'
       and policy.polpermissive
       and policy.polroles = array['authenticated'::regrole::oid]
       and policy.polqual is null
       and pg_catalog.md5(
             pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid)
           ) = '64f6778971e136463d322c17b734dc76'
  ) then
    raise exception 'supplier ACL reconciliation failed: organizer review policy contract';
  end if;

  if (
    select pg_catalog.md5(p.prosrc)
      from pg_catalog.pg_proc as p
     where p.oid = 'public.airfnb_can_manage_truck(text)'::regprocedure
  ) <> '982caee25d35d0ac9dfe1d3a343ab0a5' then
    raise exception 'supplier ACL reconciliation failed: ownership helper changed';
  end if;

  for v_function in
    select *
      from (values
        ('public.airfnb_supplier_services(uuid)'::regprocedure, 's'::"char", array['authenticated']::name[]),
        ('public.airfnb_public_service_detail(text)'::regprocedure, 's'::"char", array['anon','authenticated']::name[]),
        ('public.airfnb_invitation_candidates(uuid)'::regprocedure, 's'::"char", array['authenticated']::name[]),
        ('public.airfnb_invite_request_services(uuid,uuid[])'::regprocedure, 'v'::"char", array['authenticated']::name[]),
        ('public.airfnb_booking_service_context(uuid)'::regprocedure, 's'::"char", array['authenticated']::name[]),
        ('public.airfnb_request_application_service_context(uuid)'::regprocedure, 's'::"char", array['authenticated']::name[]),
        ('public.airfnb_supplier_export_data()'::regprocedure, 's'::"char", array['authenticated']::name[])
      ) as expected(function_oid, volatility, grantees)
  loop
    if exists (
      select 1
        from pg_catalog.pg_proc as p
       where p.oid = v_function.function_oid
         and (
           p.proowner <> v_owner
           or not p.prosecdef
           or p.provolatile <> v_function.volatility
           or p.proconfig is distinct from array['search_path=""']::text[]
         )
    ) or exists (
      select 1
        from pg_catalog.aclexplode((
          select coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
            from pg_catalog.pg_proc as p
           where p.oid = v_function.function_oid
        )) as privilege
       where privilege.privilege_type = 'EXECUTE'
         and (
           privilege.grantee = 0
           or (
             privilege.grantee <> v_owner
             and privilege.grantee not in (
             select role.oid
               from pg_catalog.pg_roles as role
              where role.rolname = any(v_function.grantees)
             )
           )
           or privilege.is_grantable
         )
    ) or (
      select pg_catalog.array_agg(role.rolname order by role.rolname)
        from pg_catalog.aclexplode((
          select coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
            from pg_catalog.pg_proc as p
           where p.oid = v_function.function_oid
        )) as privilege
        join pg_catalog.pg_roles as role on role.oid = privilege.grantee
       where privilege.privilege_type = 'EXECUTE'
         and privilege.grantee <> v_owner
    ) is distinct from (
      select pg_catalog.array_agg(expected_role.role_name order by expected_role.role_name)
        from pg_catalog.unnest(v_function.grantees) as expected_role(role_name)
    ) then
      raise exception 'supplier ACL reconciliation failed: function contract %', v_function.function_oid;
    end if;
  end loop;

  if (
    select pg_catalog.md5(p.prosrc)
      from pg_catalog.pg_proc as p
     where p.oid = 'public.airfnb_reconcile_stripe_event(text,text,timestamptz,uuid,uuid,uuid,text,bigint,text,text,bigint)'::regprocedure
  ) <> '296b93ed41a788acf9ecb099e78695ff' then
    raise exception 'supplier ACL reconciliation failed: Stripe function changed';
  end if;
end
$postconditions$;

commit;
