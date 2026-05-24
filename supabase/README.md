# Supabase

Schema completo do Air F&B, prefixado `airfnb_` para coexistir com outras apps no mesmo cluster.

## Estrutura

```
migrations/        # 13 ficheiros SQL ordenados (timestamp_name.sql)
functions/         # edge functions: send-email, stripe-webhook
config.toml.example
```

## Aplicar num projecto fresh

```bash
# 1. Linkar projecto
supabase link --project-ref <YOUR_REF>

# 2. Aplicar migrações por ordem
supabase db push

# 3. Deploy edge functions
supabase functions deploy send-email
supabase functions deploy stripe-webhook
```

## Resumo das migrações

| # | Nome | Conteúdo |
|---|---|---|
| 01 | `extensions_and_identity` | `pg_trgm`, `unaccent`, `postgis`; enum `airfnb_user_role`; tabelas `airfnb_profiles`, `airfnb_addresses` |
| 02 | `catalog` | enums `airfnb_truck_status`, `airfnb_dietary_tag`; tabelas `airfnb_categories`, `airfnb_trucks`, `airfnb_truck_categories`, `airfnb_truck_images`, `airfnb_menu_items`, `airfnb_truck_availability`, `airfnb_truck_documents` |
| 03 | `bookings_payments` | enums `airfnb_event_kind`, `airfnb_booking_status`, `airfnb_payment_status`, `airfnb_payment_method`; tabelas `airfnb_events`, `airfnb_bookings`, `airfnb_booking_trucks`, `airfnb_proposals`, `airfnb_payments`, `airfnb_invoices` |
| 04 | `messaging_reviews_content` | enums `airfnb_service_kind`, `airfnb_post_status`; tabelas `airfnb_conversations`, `airfnb_conversation_participants`, `airfnb_messages`, `airfnb_reviews`, `airfnb_favorites`, `airfnb_service_providers`, `airfnb_booking_addons`, `airfnb_blog_*`, `airfnb_faqs`, `airfnb_newsletter_subscribers`, `airfnb_contact_requests`, `airfnb_notifications`, `airfnb_audit_log` |
| 05 | `rls_triggers_seed` | RLS principal + 4 funções (`airfnb_is_admin`, `airfnb_touch_updated_at`, `airfnb_recalc_truck_rating`, `airfnb_handle_new_user`) + triggers + seed das categorias/FAQ/blog + 5 storage buckets |
| 06 | `fix_rls_and_function_security` | corrige RLS faltando em 11 tabelas + add policies em 8 tabelas sem políticas + grants das funções |
| 07 | `rls_extras_indexes_realtime_views` | RLS extra para owners (events/payments/invoices), 20 índices, realtime em messages/notifications/bookings, 2 views, RPC `airfnb_truck_is_available` |
| 08 | `seed_demo_data` | seed user admin + 12 trucks + 12 imagens + 12 links categoria + 12 menu items + 8 service providers + 5 blog posts |
| 09 | `marketplace_request_application_lockfee` | enums `airfnb_request_status`, `airfnb_application_status`, `airfnb_lock_fee_status`, `airfnb_payment_direction`, `airfnb_payment_kind`; tabelas `airfnb_event_requests`, `airfnb_applications`, `airfnb_lock_fees`, `airfnb_request_invitations`, `airfnb_truck_alert_prefs`; alterações em bookings/payments/conversations/trucks |
| 10 | `helpers_match_accept_cron` | funções `airfnb_calculate_lock_fee`, `airfnb_match_score`, `airfnb_find_matching_requests`, `airfnb_find_matching_trucks`, `airfnb_accept_application`, `airfnb_shortlist_application`, `airfnb_reject_application`, `airfnb_expire_stale_lock_fees`, `airfnb_expire_stale_requests`; 2 jobs `pg_cron` |
| 11 | `fix_function_security` | `match_score` → `SECURITY INVOKER`; revoke das funções cron de anon/authenticated |
| 12 | `deal_types_discovery_modes_split_lockfee` | enums `airfnb_deal_type`, `airfnb_discovery_mode`; colunas extra em applications/event_requests/lock_fees; reescrita de `accept_application` com split €25+€25; funções `airfnb_recommend_slots`, `airfnb_recommend_trucks_for_request`; trigger `airfnb_set_recommended_slots` |
| 13 | `fix_is_admin_grants` | regrant `execute on airfnb_is_admin` para anon+authenticated (necessário para RLS funcionar via API) |

## Edge functions — secrets

```bash
supabase secrets set RESEND_API_KEY=re_xxx
supabase secrets set FROM_EMAIL="Air F&B <ola@airfnb.example>"
supabase secrets set ALLOWED_TEMPLATES="booking_inquiry_received,proposal_sent,booking_confirmed,booking_cancelled,payment_received,review_request,contact_reply,newsletter_confirm"
supabase secrets set STRIPE_SECRET_KEY=sk_live_xxx
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_xxx
```
