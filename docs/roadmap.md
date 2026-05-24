# Air F&B — Roadmap pós-MVP

Sequência de blocos a entregar, um por PR, com loop CodeRabbit→fix→merge.

> Bloco 0 (MVP scaffold) — concluído no PR #2.

| # | Bloco | Estado |
|---|---|---|
| 1 | **Onboarding & Auth** — OAuth Google + Apple, recovery + magic link, wizards (organizer / truck), avatar upload (compressão client-side ≤2MB), email-confirmation toggle | em curso (PR #3) |
| 2 | **Truck Owner** — galeria de fotos (Supabase Storage, compressão ≤2MB), editor de menu, calendário de disponibilidade, docs com expiração, prefs de alerta, página de receitas, replies a reviews, status active/paused | pendente |
| 3 | **Organizer** — tabela compare candidaturas, convidar trucks do catálogo, edit/cancel pedido, re-publicar, painel sugeridos, PDF do brief, histórico | pendente |
| 4 | **Marketplace flow** — withdraw application, contra-proposta, edit application, match-score visível, chat pré-aceitação | pendente |
| 5 | **Pagamentos & finança** — Stripe deploy completo + webhook live, MB Way + Multibanco (Stripe), fatura PDF com NIF, refund automático, escrow opcional para v2. **Paywall fica em aberto — ifthenpay como provider alternativo a avaliar** | pendente |
| 6 | **Chat & Notificações** — `/dashboard/conversas` index, badge de não-lidas realtime no header, anexos imagem, PWA push, digest semanal email, settings de notificações | pendente |
| 7 | **Reviews & Trust** — review **bidirecional** (truck→organizer e organizer→truck) com fotos, selos verificação (ASAE/HACCP/seguro), trust score, reminders por email, moderação admin | pendente |
| 8 | **Descoberta & SEO** — mapa Mapbox, search bar global, filtros dietéticos, landing pages por cidade + categoria, OG + structured data, i18n PT/EN/ES, sitemap | pendente |
| 9 | **Anti-spam & Qualidade** — `airfnb_can_apply` quotas, subscription tiers (Basic/Pro/Featured), verificação telefone, validação NIF, **multi-truck por empresa** (uma empresa pode gerir vários trucks) | pendente |
| 10 | **Admin** — dashboard KPIs, fila de moderação, mediação de disputas, user management, exports CSV, audit log viewer | pendente |
| 11 | **Mobile / PWA** — bottom nav, header colapsado, PWA manifest + SW, push notifications, app shells Capacitor (iOS/Android) | pendente |
| 12 | **Marketing & Conteúdo** — pricing calculator interactive, editor blog admin, lead magnet PDF, newsletter Brevo, showcase eventos passados | pendente |
| 13 | **Integrações** — WhatsApp Business floater, **Google Calendar** (substituto gratuito do Calendly para chamadas com a equipa + sync com calendário do truck), Instagram feed embed | pendente |
| 14 | **Legal & Compliance** — cookie banner GDPR, Termos + Privacidade reais, GDPR data export + deletion | pendente |
| 15 | **Performance & DX** — `next/image` Supabase loader, loading skeletons, Sentry, Plausible, types regen automatizado | pendente |
| 16 | **Design Polish (Claude visual review)** — auditoria visual de cada página, identificar inconsistências (spacing/typography/contraste/hierarquia), produzir relatório de microfixes (**sem redesign, sem mudar branding**), aplicar correções | pendente |

## Notas

- **Lock fee modelo final**: pode ser fixo OU percentagem OU mix (fixed + variable). Plataforma cobra €25 da margem própria + €25 cobrado em nome do organizer (descontado no valor que o truck deve ao organizer). Total: €50 que o truck paga via Stripe quando é aceite.
- **Modos descoberta**: `curated` (organizer escolhe trucks) + `broadcast` (todos matching avisados) activos no MVP. `auto_match` no schema mas inactivo na UI.
- **Multi-truck por empresa** (bloco 9): vai exigir alterações de schema — provavelmente `airfnb_companies` separadas de `airfnb_profiles`, com `airfnb_trucks.company_id` em vez de `owner_id`.
- **Reviews bidirecionais** (bloco 7): nova tabela `airfnb_organizer_reviews` espelho da `airfnb_reviews` (truck escreve sobre organizer) + campo composite em `airfnb_profiles`.
