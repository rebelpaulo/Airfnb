-- Bound uploads at the Storage service, not only in browser code. The image
-- uploaders currently re-encode to JPEG/WebP/PNG below 2 MiB; compliance
-- documents accept PDFs below 8 MiB.
update storage.buckets
set file_size_limit = 2 * 1024 * 1024,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']::text[]
where id in (
  'airfnb-truck-images',
  'airfnb-menu-images',
  'airfnb-blog-images',
  'airfnb-avatars'
);

update storage.buckets
set file_size_limit = 8 * 1024 * 1024,
    allowed_mime_types = array['application/pdf']::text[]
where id = 'airfnb-documents';

-- A safe, narrow predicate shared by child-table and Storage-object read
-- policies. It accepts malformed paths without raising and only reveals the
-- same active/owner/admin state already exposed by the catalog.
create or replace function public.airfnb_can_read_truck_child(p_truck_text text)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_truck_id uuid;
begin
  if p_truck_text is null
     or p_truck_text !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    return false;
  end if;

  v_truck_id := p_truck_text::uuid;

  return exists (
    select 1
    from public.airfnb_trucks as truck
    where truck.id = v_truck_id
      and (
        truck.status = 'active'
        or truck.owner_id = (select auth.uid())
        or public.airfnb_is_admin()
      )
  );
end;
$$;

revoke all on function public.airfnb_can_read_truck_child(text) from public;
grant execute on function public.airfnb_can_read_truck_child(text) to anon, authenticated;

-- Draft child rows must not enumerate through the Data API. Existing owner
-- write policies still provide the owner/admin SELECT needed by management
-- screens; this read policy is the public catalog path.
drop policy if exists "airfnb_truck_images_read" on public.airfnb_truck_images;
create policy "airfnb_truck_images_read"
on public.airfnb_truck_images
for select
to anon, authenticated
using (public.airfnb_can_read_truck_child(truck_id::text));

drop policy if exists "airfnb_menu_items_read" on public.airfnb_menu_items;
create policy "airfnb_menu_items_read"
on public.airfnb_menu_items
for select
to anon, authenticated
using (public.airfnb_can_read_truck_child(truck_id::text));

drop policy if exists "airfnb_truck_cat_read" on public.airfnb_truck_categories;
create policy "airfnb_truck_cat_read"
on public.airfnb_truck_categories
for select
to anon, authenticated
using (public.airfnb_can_read_truck_child(truck_id::text));

-- The bucket remains public because catalog URLs depend on that contract, but
-- object listing through the Storage API now follows the parent truck state.
-- A known public object URL remains retrievable by design.
drop policy if exists "airfnb_truck_images_public_read" on storage.objects;
create policy "airfnb_truck_images_public_read"
on storage.objects
for select
to anon, authenticated
using (
  bucket_id = 'airfnb-truck-images'
  and public.airfnb_can_read_truck_child(split_part(name, '/', 1))
);

-- The counter is an internal implementation detail. There are deliberately no
-- client policies; trigger functions run as their owner and trusted server
-- ingestion uses the service role.
alter table public.airfnb_rate_limits enable row level security;

do $$
declare
  policy_row record;
begin
  for policy_row in
    select policyname
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'airfnb_rate_limits'
  loop
    execute format(
      'drop policy %I on public.airfnb_rate_limits',
      policy_row.policyname
    );
  end loop;
end;
$$;

revoke all on table public.airfnb_rate_limits from public, anon, authenticated;
grant select, insert, update, delete on table public.airfnb_rate_limits to service_role;

create or replace function public.airfnb_check_rate_limit(
  p_action text,
  p_bucket text,
  p_limit_per_window integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_count integer;
begin
  if p_action is null
     or btrim(p_action) = ''
     or char_length(p_action) > 64
     or p_bucket is null
     or btrim(p_bucket) = ''
     or char_length(p_bucket) > 160
     or p_limit_per_window is null
     or p_limit_per_window < 1
     or p_limit_per_window > 10000
     or p_window_seconds is null
     or p_window_seconds < 1
     or p_window_seconds > 2678400 then
    raise exception using
      errcode = '22023',
      message = 'invalid rate-limit parameters';
  end if;

  insert into public.airfnb_rate_limits (action, bucket, count, window_at)
  values (p_action, p_bucket, 1, statement_timestamp())
  on conflict (action, bucket) do update
    set count = case
                  when public.airfnb_rate_limits.window_at
                       < statement_timestamp() - (p_window_seconds * interval '1 second')
                  then 1
                  else public.airfnb_rate_limits.count + 1
                end,
        window_at = case
                      when public.airfnb_rate_limits.window_at
                           < statement_timestamp() - (p_window_seconds * interval '1 second')
                      then statement_timestamp()
                      else public.airfnb_rate_limits.window_at
                    end
  returning count into v_count;

  return v_count <= p_limit_per_window;
end;
$$;

revoke all on function public.airfnb_check_rate_limit(text, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.airfnb_check_rate_limit(text, text, integer, integer)
  to service_role;

-- Public ingestion is server-mediated from this point onward. Admin read/update
-- policies remain intact; only direct untrusted INSERT paths are removed.
drop policy if exists airfnb_partner_leads_insert on public.airfnb_partner_leads;
drop policy if exists "airfnb_newsletter_anyone_insert" on public.airfnb_newsletter_subs;
drop policy if exists "airfnb_newsletter_insert_any" on public.airfnb_newsletter_subscribers;
drop policy if exists "airfnb_contact_insert_any" on public.airfnb_contact_requests;

revoke insert on table public.airfnb_partner_leads from public, anon, authenticated;
revoke insert on table public.airfnb_newsletter_subs from public, anon, authenticated;
revoke insert on table public.airfnb_newsletter_subscribers from public, anon, authenticated;
revoke insert on table public.airfnb_contact_requests from public, anon, authenticated;

grant insert on table public.airfnb_partner_leads to service_role;
grant select, insert, update on table public.airfnb_newsletter_subs to service_role;
grant insert on table public.airfnb_newsletter_subscribers to service_role;
grant insert on table public.airfnb_contact_requests to service_role;
