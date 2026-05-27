-- The kind='truck' placeholder seed previously pointed to the bundled
-- SVG (/truck-placeholder.svg). PR #56 + the design team now ship a
-- realistic 3D render of the airfb-branded truck as PNG, which the
-- carousel + lightbox handle better than an SVG (no sandbox CSP
-- needed, optimised through next/image). Repoint every existing
-- placeholder row to the new file and update the column comment.
--
-- Idempotent: only touches rows that still hold the SVG path.

update public.airfnb_truck_images
   set url = '/truck-placeholder.png'
 where kind = 'truck'
   and url = '/truck-placeholder.svg';
