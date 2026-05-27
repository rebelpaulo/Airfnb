-- Restore the truck-kind row that PR #46 tried (and failed) to seed
-- with hand-picked Unsplash URLs. This time we use the bundled
-- /truck-placeholder.png shipped in /public — it's a stylised
-- food-truck illustration the design team already approved as the
-- generic stand-in. Result on the catalogo / procurar cards:
--   * cover_url picks the placeholder (kind='truck' wins the view's rank)
--   * gallery_urls returns [placeholder, food] so the carousel has
--     two photos and renders its chevrons + dots
--   * owners replace the placeholder by uploading a real exterior
--     shot via the wizard kind picker (PR #47)
--
-- Idempotent via the (-1) sort_order marker we use for seed rows.

-- Only seed for trucks that have ZERO kind='truck' images. Skips any
-- truck where an owner has already uploaded a real exterior shot — we
-- don't want the placeholder competing with (and beating, since its
-- sort_order=-1 sorts earlier) a real photo. The NOT EXISTS predicate
-- also makes the migration idempotent on its own without leaning on a
-- unique constraint the table doesn't have.
insert into public.airfnb_truck_images (truck_id, url, alt, is_cover, sort_order, kind)
select t.id, '/truck-placeholder.png', t.name || ' (truck)', false, -1, 'truck'
  from public.airfnb_trucks t
 where t.status = 'active'
   and not exists (
     select 1 from public.airfnb_truck_images i
      where i.truck_id = t.id and i.kind = 'truck'
   );
