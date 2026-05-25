-- Split address into personal vs billing on airfnb_profiles, so the
-- /dashboard/perfil page can present them in distinct tabs (mirroring the
-- original site's "Informações Gerais" vs "Informações de Faturação").
--
-- Both nullable; no backfill needed — users fill in as they reach the page.
-- Existing company_name and vat_number are billing fields already.

alter table public.airfnb_profiles
  add column if not exists address_line text,
  add column if not exists billing_address_line text;
