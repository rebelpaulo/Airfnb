-- airfnb_18: storage RLS for the truck-images and documents buckets.
--
-- Path conventions enforced by the policies (the wizard writes these paths):
--   airfnb-truck-images : "<truck_id>/<filename>"
--   airfnb-documents    : "<truck_id>/<kind>-<timestamp>.<ext>"
--
-- We look up airfnb_trucks.owner_id from the first path segment instead of
-- comparing against auth.uid() directly because trucks are owned by a profile
-- and storage objects belong to a truck, not a user.
--
-- airfnb-truck-images is a public bucket (the catalog renders the URLs
-- directly), so SELECT is unrestricted; writes must come from the truck owner
-- or an admin. airfnb-documents is private — only the truck owner and admins
-- can read or write (signed URLs are issued from the server when needed).

create or replace function public.airfnb_is_truck_owner(p_truck_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.airfnb_trucks
     where id = p_truck_id
       and owner_id = auth.uid()
  );
$$;
revoke all on function public.airfnb_is_truck_owner(uuid) from public;
grant execute on function public.airfnb_is_truck_owner(uuid) to authenticated;

-- ---------- airfnb-truck-images (public-read, owner-write) ----------
do $$ begin
  begin
    create policy "airfnb_truck_images_public_read"
      on storage.objects for select
      using (bucket_id = 'airfnb-truck-images');
  exception when duplicate_object then null; end;

  begin
    create policy "airfnb_truck_images_owner_insert"
      on storage.objects for insert to authenticated
      with check (
        bucket_id = 'airfnb-truck-images'
        and public.airfnb_is_truck_owner(split_part(name, '/', 1)::uuid)
      );
  exception when duplicate_object then null; end;

  begin
    create policy "airfnb_truck_images_owner_update"
      on storage.objects for update to authenticated
      using (
        bucket_id = 'airfnb-truck-images'
        and public.airfnb_is_truck_owner(split_part(name, '/', 1)::uuid)
      )
      with check (
        bucket_id = 'airfnb-truck-images'
        and public.airfnb_is_truck_owner(split_part(name, '/', 1)::uuid)
      );
  exception when duplicate_object then null; end;

  begin
    create policy "airfnb_truck_images_owner_delete"
      on storage.objects for delete to authenticated
      using (
        bucket_id = 'airfnb-truck-images'
        and public.airfnb_is_truck_owner(split_part(name, '/', 1)::uuid)
      );
  exception when duplicate_object then null; end;
end $$;

-- ---------- airfnb-documents (private — owner-only read/write) ----------
do $$ begin
  begin
    create policy "airfnb_documents_owner_read"
      on storage.objects for select to authenticated
      using (
        bucket_id = 'airfnb-documents'
        and public.airfnb_is_truck_owner(split_part(name, '/', 1)::uuid)
      );
  exception when duplicate_object then null; end;

  begin
    create policy "airfnb_documents_owner_insert"
      on storage.objects for insert to authenticated
      with check (
        bucket_id = 'airfnb-documents'
        and public.airfnb_is_truck_owner(split_part(name, '/', 1)::uuid)
      );
  exception when duplicate_object then null; end;

  begin
    create policy "airfnb_documents_owner_update"
      on storage.objects for update to authenticated
      using (
        bucket_id = 'airfnb-documents'
        and public.airfnb_is_truck_owner(split_part(name, '/', 1)::uuid)
      )
      with check (
        bucket_id = 'airfnb-documents'
        and public.airfnb_is_truck_owner(split_part(name, '/', 1)::uuid)
      );
  exception when duplicate_object then null; end;

  begin
    create policy "airfnb_documents_owner_delete"
      on storage.objects for delete to authenticated
      using (
        bucket_id = 'airfnb-documents'
        and public.airfnb_is_truck_owner(split_part(name, '/', 1)::uuid)
      );
  exception when duplicate_object then null; end;
end $$;
