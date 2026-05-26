-- Hotfix for PR #46 / migration airfnb_43: the URLs I seeded into
-- airfnb_truck_images with kind='truck' were guesses based on memory of
-- Unsplash IDs, not verified entries. Five of seven returned 404 in
-- production and the two that DID resolve were unrelated content
-- (one was a dog photo, reported by the user).
--
-- Remove them so the airfnb_v_truck_card view's cover_url ranking
-- falls back to kind='food' images (which were curated and known to
-- work). The TruckPhotoUpload wizard (PR #47) lets owners upload real
-- exterior shots and tag them as kind='truck' — that's how trucks
-- should get the proper "truck-first" cover going forward, not via
-- seed guesses.
--
-- Idempotent: if a future migration re-adds verified truck images,
-- this DELETE only touches rows that match the broken-seed pattern
-- (sort_order = -1, which was unique to that seed insert).

delete from public.airfnb_truck_images
 where kind = 'truck'
   and sort_order = -1;
