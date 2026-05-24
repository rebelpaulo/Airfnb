# Air F&B

Marketplace de Food Trucks para eventos — modelo **reverse marketplace** (organizer publica brief → trucks aplicam → organizer escolhe → truck paga lock-fee).

## Stack

- **Next.js 15** (App Router, React 19, Server Actions)
- **Supabase** — Postgres + Auth + Storage + Realtime + Edge Functions
- **Tailwind-free** global CSS (1300+ linhas de design system custom)
- **Stripe** (lock-fee checkout) — configurável; modo dev disponível
- **Resend** (email transacional) — opcional

## Estrutura

```
app/              # Next.js routes (App Router)
components/       # React components (Header, Footer)
lib/              # supabase clients, money/img/recommend helpers
types/            # TypeScript types do schema airfnb_*
supabase/
  schema.sql      # schema completo (referência)
  functions/      # edge functions: send-email, stripe-webhook
docs/
  marketplace-pivot-plan.md
```

## Setup local

```bash
pnpm install
cp .env.local.example .env.local
# preencher SUPABASE_SERVICE_ROLE_KEY (Stripe + Resend são opcionais)
pnpm dev   # http://localhost:3001
```

## Schema

Todas as tabelas prefixadas com `airfnb_` (multi-projecto no mesmo cluster Supabase).
30 tabelas + 4 enums + 2 views + 6 RPCs + 2 cron jobs.

Migrações aplicadas via Supabase MCP (ver `docs/marketplace-pivot-plan.md` para detalhe).
