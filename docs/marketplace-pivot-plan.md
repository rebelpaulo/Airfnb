# F&B Tailor — Pivot para Marketplace de Pedidos

> **Modelo:** organizer publica brief → trucks aplicam → organizer escolhe → truck paga lock-fee → booking confirmado.
> **Referências:** Add to Event (UK), Thumbtack, GigSalad, The Bash.

---

## 1. Mental model

```
ORGANIZER                  PLATAFORMA                 TRUCK
─────────                  ──────────                 ─────
publica brief    ──────▶   /pedidos (feed)   ──────▶  vê alerta
                                                       │
                                                       ▼
                           airfnb_applications  ◀───── aplica c/ preço + menu
                                  │
recebe candidaturas ◀─────────────┤
compara/shortlist                 │
escolhe        ──────▶  application.status='accepted'
                                  │
                           cria booking ('pending_lock_fee')
                           cria lock_fee (due_until = +48h)
                                  │
                                  │   notifica truck
                                  ▼
                                                       paga lock-fee (Stripe)
                                  ▼
                           webhook: lock_fee='paid'
                           booking.status='confirmed'
                                  │
                                  ▼
chat 1-a-1 (organizer ↔ truck) — airfnb_conversations
                                  │
                                  ▼
                           evento → completed → review
```

### Variantes do fluxo
- **Invite-only**: organizer marca o pedido como privado e convida trucks específicos do catálogo (`airfnb_request_invitations`).
- **Multi-slot**: pedido pede 3 trucks → organizer pode aceitar 3 candidaturas; cada uma gera o seu booking + lock fee.
- **Lock fee expira**: passa o prazo, application='expired', organizer pode aceitar próxima da shortlist sem ficar bloqueado.

---

## 2. Schema — deltas

### Novas tabelas (migração 09)

| Tabela | Propósito | Campos principais |
|---|---|---|
| `airfnb_event_requests` | O brief publicado pelo organizer | `organizer_id`, `title`, `kind`, `start_at`, `city`, `expected_pax`, `slots_needed`, `budget_min/max`, `desired_categories[]`, `dietary_requirements[]`, `applications_deadline`, `power_available`, `water_available`, `status`, `visibility` |
| `airfnb_applications` | Candidatura de um truck a um request | `request_id`, `truck_id`, `proposed_price`, `cover_message`, `menu_pitch jsonb`, `estimated_servings`, `available_confirmed`, `status`, `shortlisted_at`, `decided_at`, `withdrawn_at`. UNIQUE `(request_id, truck_id)` |
| `airfnb_lock_fees` | Taxa que o truck paga ao ser aceite | `application_id` (UNIQUE), `amount`, `currency`, `due_until`, `status`, `paid_at`, `provider_ref`, `refunded_at` |
| `airfnb_request_invitations` | Curadoria — organizer convida trucks | PK `(request_id, truck_id)`, `invited_by`, `invited_at`, `responded` |
| `airfnb_truck_alert_prefs` | Filtros de notificação do truck | `truck_id` (PK), `cities[]`, `categories[]`, `min_budget`, `max_radius_km`, `channels jsonb` |

### Novos enums
- `airfnb_request_status` — `draft`, `open`, `reviewing`, `awarded`, `closed`, `expired`, `cancelled`
- `airfnb_application_status` — `submitted`, `shortlisted`, `accepted`, `rejected`, `withdrawn`, `expired`
- `airfnb_lock_fee_status` — `pending`, `paid`, `expired`, `refunded`, `waived`
- `airfnb_payment_direction` — `organizer_to_platform`, `truck_to_platform`, `platform_to_truck`
- `airfnb_payment_kind` — `lock_fee`, `event_payment`, `payout`, `refund`
- novos valores em `airfnb_booking_status`: `pending_lock_fee` (entre `accepted` e `confirmed`)

### Mudanças em tabelas existentes

| Tabela | Alteração |
|---|---|
| `airfnb_bookings` | + `application_id uuid REFERENCES airfnb_applications(id)` |
| `airfnb_payments` | + `direction airfnb_payment_direction`, + `kind airfnb_payment_kind DEFAULT 'event_payment'` |
| `airfnb_conversations` | + `application_id uuid REFERENCES airfnb_applications(id)` (chat pode começar antes de existir booking) |
| `airfnb_trucks` | + `lead_response_rate numeric(3,2)`, + `last_active_at timestamptz`, + `subscription_tier text default 'basic'` |
| `airfnb_events` | **mantém-se** mas só usado pós-booking (entidade "evento final") — opcional, pode ser derivado de `event_requests` |

### Deprecada
- `airfnb_proposals` — semântica substituída por `airfnb_applications`. Não dropar (pode haver dados); marcar como legado no código.

---

## 3. RLS principais

| Tabela | SELECT | INSERT | UPDATE |
|---|---|---|---|
| `airfnb_event_requests` | público se `status IN ('open','reviewing')` e `visibility='public'`; organizer da própria; trucks convidados | organizer | organizer ou admin |
| `airfnb_applications` | truck dono da candidatura; organizer do request; admin | truck (com check `truck.owner_id=auth.uid()`) | truck (só `withdraw`); organizer (`shortlist`/`accept`/`reject`); admin |
| `airfnb_lock_fees` | truck (via application); organizer (via request); admin | só `service_role` | só `service_role` (webhook) |
| `airfnb_request_invitations` | truck convidado; organizer; admin | organizer | truck (marca `responded=true`) |
| `airfnb_truck_alert_prefs` | dono do truck | dono do truck | dono do truck |

---

## 4. Helper functions / RPCs

- `airfnb_calculate_lock_fee(application_id) → numeric` — default `10% × proposed_price`, com floor de `€25`
- `airfnb_match_score(truck_id, request_id) → numeric` — 0-100 baseado em: categoria match, cidade dentro do raio, capacidade ≥ pax, disponibilidade na data, rating do truck
- `airfnb_find_matching_requests(truck_id) → setof event_requests` — feed do truck
- `airfnb_find_matching_trucks(request_id) → setof trucks` — sugestões para o organizer convidar
- `airfnb_accept_application(application_id)` — transação: atualiza application, cria booking `pending_lock_fee`, cria lock_fee, envia notificações

---

## 5. Páginas — diff sobre o site actual

### Novas páginas (10)
| Rota | Quem | Função |
|---|---|---|
| `/publicar` | Organizer | Wizard 6 passos para criar request |
| `/pedidos` | Trucks (público) | Feed de pedidos abertos, com filtros |
| `/pedidos/[id]` | Público | Detalhe do pedido + botão "Aplicar" |
| `/pedidos/[id]/aplicar` | Truck logado | Form de candidatura |
| `/dashboard/organizer` | Organizer | Os meus pedidos, status, candidaturas recebidas |
| `/dashboard/organizer/pedidos/[id]` | Organizer | Comparar candidaturas side-by-side, shortlist, escolher |
| `/dashboard/truck` | Truck owner | Feed de pedidos matched, minhas candidaturas, ganhos |
| `/dashboard/truck/aplicacoes` | Truck owner | Listagem das minhas candidaturas + status |
| `/dashboard/truck/lock/[id]` | Truck owner | Checkout Stripe do lock fee |
| `/dashboard/admin/disputas` | Admin | Mediação e métricas |

### Páginas a refazer (3)
| Página | Mudança |
|---|---|
| `/` (home) | **Hero dual** — "Tens um evento? Publica grátis" + "Tens um Food Truck? Ganha eventos". Search bar atual desce ou desaparece. "Como funciona" passa a ter 2 tabs (organizer / truck). |
| `/organizeEvent` | Redireciona para `/publicar` ou vira landing alta-conversão para esse funil |
| `/addTruck` | Vira landing do funil truck — foco em "Quantos eventos podes ganhar" |

### Páginas que se mantêm como estão (10)
`/catalogo` (passa a portfolio secundário), `/blog`, `/sobre-nos`, `/equipa`, `/ajuda`, `/reservar` (vira `/publicar` ou remove), `/encontrar-espaco`, `/gestao-convidados`, `/musica-animacao`, `/marketing`, `/privacidade`.

---

## 6. API / Edge functions adicionais

- `accept-application` — RPC seguro que faz a transação atómica
- `process-lock-fee-expiry` — pg_cron diário marca `expired` os lock fees não pagos passado o prazo
- `notify-matching-trucks` — trigger em `event_requests INSERT` → envia push/email a trucks com match
- `weekly-truck-digest` — pg_cron semanal, resumo de pedidos relevantes ao truck

---

## 7. Business model

| Item | Valor |
|---|---|
| Organizer | **Grátis** publicar + comunicar |
| Truck — listagem básica | Grátis |
| Truck — lock fee | **10% do valor proposto** (mín €25, máx €500) |
| Truck — featured (opcional) | Subscrição mensal — fica no topo do feed |
| Truck — créditos extra de aplicação (opcional) | Pode aplicar a >5 pedidos/semana mediante créditos |

Métricas alvo após 6 meses:
- 200+ requests/mês
- 5-8 candidaturas/request
- 60% requests com pelo menos 1 lock fee pago
- LTV médio truck > €600/mês

---

## 8. Trabalho em sequência

1. **Migração 09** — novas tabelas + enums + RLS + indexes ✅ (a aplicar agora)
2. **Migração 10** — helper functions + match score + pg_cron ⏳
3. **Edge functions** — `accept-application`, `process-lock-fee-expiry`, `notify-matching-trucks` ⏳
4. **Refazer hero da home** ⏳
5. **Novas páginas** (10) ⏳
6. **Dashboards** ⏳
7. **Stripe Checkout para lock fee** ⏳

---

## 9. Open questions para validares

1. **Lock fee** — 10% do preço proposto faz sentido? Ou flat €50?
2. **Janela de pagamento** — 48h para pagar lock fee é razoável?
3. **Anti-spam de candidaturas** — limitar a 5/semana por truck no plano gratuito?
4. **Visibilidade do preço** dos concorrentes — os trucks vêem o preço das outras candidaturas no mesmo request, ou só o organizer?
5. **Mediação financeira** — o pagamento do evento (organizer → truck) passa pela plataforma (escrow) ou é tratado offline entre os dois?
6. **Slots múltiplos** — quando um pedido pede 3 trucks, pode aceitar 3 candidaturas distintas? E se chegarem 3 candidaturas iguais, escolhe-se por critério?
7. **Cancelamento pelo truck** depois de pagar lock fee — devolve o lock fee? Total / parcial?

---

## 10. Decisões nas 3 open questions pendentes (recomendação)

### 10.1 Anti-spam de candidaturas
**Recomendação:** limitar trucks free a **5 candidaturas activas/semana** + 1 candidatura/request. Adicionar campo `airfnb_trucks.subscription_tier` (já criado em migração 09) com valores `basic` (free, limite 5/sem), `pro` (€19/mês, ilimitado + 2x mais visibilidade no feed), `featured` (€49/mês, topo + boost de match_score).

**Quality gates** (independentes do tier):
- `cover_message` mínimo 50 caracteres (já no form, falta no constraint SQL)
- Só pode aplicar se `airfnb_trucks.status='active'` e tiver pelo menos uma `truck_images.is_cover=true`
- `homologation_expires_at > now()` (ASAE/HACCP em dia)

**Como implementar:** função RPC `airfnb_can_apply(truck_id) → boolean` chamada pelo wizard antes de mostrar o botão "Aplicar", e check duplicado na policy `airfnb_app_insert`.

### 10.2 Mediação financeira pós-evento
**Recomendação para MVP:** mediação **offline entre truck e organizer**. A plataforma só toca dinheiro no lock-fee (€50 ao truck). O restante do pagamento (truck → organizer ou organizer → truck consoante o tipo de deal) acontece directamente entre os dois, em cash/transferência/MB Way no dia do evento.

**Porquê:** mediação completa exige Stripe Connect + KYC dos trucks + registo como PSP/marketplace agent + AML compliance. Ganhar 30k€ a 6 meses para depois bloquear no compliance é mau ROI.

**Roadmap v2 (3-6 meses)**:
- Lançar opção "Pagamento Garantido" como feature paga (Pro tier)
- Organizer paga total à plataforma via escrow
- Plataforma liberta ao truck 24h após confirmação do evento concluído
- Resolve disputas (Pro = SLA 24h)
- Mantém modelo MVP a correr em paralelo para deals não-garantidos

### 10.3 Cancelamento pelo truck depois de pagar lock-fee

| Janela antes do evento | Reembolso | Penalização |
|---|---|---|
| > 14 dias | 100% (€50 → volta ao truck) | — |
| 7-14 dias | 50% (€25 → volta) | -0.2 no rating_avg; -10 em match_score 60 dias |
| < 7 dias | 0% | -0.5 no rating_avg; -25 em match_score 90 dias; 30 dias suspenso |
| < 24h ou no-show | 0% + penalty fee €100 extra | suspenso 90 dias; review pública negativa automática |

**Implementação:** acrescentar enum `airfnb_cancellation_window` e função `airfnb_cancel_application_by_truck(application_id, reason)` que aplica refund + penalty conforme a janela. Trigger automático reabre o slot do request — se ainda houver candidaturas em shortlist, organizer pode aceitar a próxima sem perder tempo.

**Cancelamento pelo organizer:** se já houver bookings confirmadas, organizer perde os €25 adiantados (mantidos como compensação ao truck). Editar/cancelar pedidos sem ainda haver lock-fee paga é grátis.
