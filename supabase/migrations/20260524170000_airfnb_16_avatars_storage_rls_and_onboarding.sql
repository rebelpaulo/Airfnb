-- airfnb_16_avatars_storage_rls_and_onboarding
-- applied at 20260524170000

-- 1. Onboarding flag on profiles
alter table public.airfnb_profiles
  add column if not exists onboarding_completed boolean default false;

-- 2. Storage RLS for the airfnb-avatars bucket: public read, owner-only write.
--    Path convention is `<user_id>/<filename>`; the policies enforce that
--    by parsing the first segment of `name` and comparing to auth.uid().
do $$ begin
  begin
    create policy "airfnb_avatars_public_read"
      on storage.objects for select
      using (bucket_id = 'airfnb-avatars');
  exception when duplicate_object then null; end;

  begin
    create policy "airfnb_avatars_owner_insert"
      on storage.objects for insert
      with check (
        bucket_id = 'airfnb-avatars'
        and auth.uid() is not null
        and split_part(name, '/', 1) = auth.uid()::text
      );
  exception when duplicate_object then null; end;

  begin
    create policy "airfnb_avatars_owner_update"
      on storage.objects for update
      using (
        bucket_id = 'airfnb-avatars'
        and split_part(name, '/', 1) = auth.uid()::text
      )
      with check (
        bucket_id = 'airfnb-avatars'
        and split_part(name, '/', 1) = auth.uid()::text
      );
  exception when duplicate_object then null; end;

  begin
    create policy "airfnb_avatars_owner_delete"
      on storage.objects for delete
      using (
        bucket_id = 'airfnb-avatars'
        and split_part(name, '/', 1) = auth.uid()::text
      );
  exception when duplicate_object then null; end;
end $$;
