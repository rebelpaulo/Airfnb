-- Restore the truck-kind row that PR #46 tried (and failed) to seed
-- with hand-picked Unsplash URLs. This time we use the bundled
-- /truck-placeholder.svg shipped in /public — it's a stylised
-- food-truck illustration the design team already approved as the
-- generic stand-in. Result on the catalogo / procurar cards:
--   * cover_url picks the placeholder (kind='truck' wins the view's rank)
--   * gallery_urls returns [placeholder, food] so the carousel has
--     two photos and renders its chevrons + dots
--   * owners replace the placeholder by uploading a real exterior
--     shot via the wizard kind picker (PR #47)
--
-- Idempotent via the (-1) sort_order marker we use for seed rows.

insert into public.airfnb_truck_images (truck_id, url, alt, is_cover, sort_order, kind)
select t.id, '/truck-placeholder.svg', t.name || ' (truck)', false, -1, 'truck'
  from public.airfnb_trucks t
  where t.status = 'active'
on conflict do nothing;
