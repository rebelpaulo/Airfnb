# F&B Tailor

Marketplace de Food Trucks, Catering e Bares para Eventos. O fluxo principal é um reverse marketplace: o organizador publica um brief, fornecedores elegíveis candidatam-se, o organizador escolhe e o fornecedor confirma a reserva através do lock-fee.

## Stack e estrutura

- Next.js 15 (App Router, React 19 e Server Actions)
- Supabase (Postgres, Auth, Storage e Edge Functions)
- Stripe Checkout e webhooks para o lock-fee
- Resend para email transacional

```text
app/                 rotas Next.js
components/          componentes partilhados
lib/                 integrações e regras server-side
supabase/migrations/ migrações incrementais
supabase/functions/  send-email e stripe-webhook
tests/               testes de regressão executáveis com node:test
```

## Desenvolvimento local

```bash
pnpm install
cp .env.local.example .env.local
pnpm dev
```

A aplicação local usa `http://localhost:3001`. Não colocar valores reais em `.env.local.example` nem no repositório.

## Contrato de configuração

| Variável | Consumidor real | Obrigatória em produção |
| --- | --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | clientes Supabase browser/server e envio de leads | sim |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | clientes Supabase browser/server | sim |
| `SUPABASE_SERVICE_ROLE_KEY` | rotas server-side, rate-limit, Stripe e invocação de email | sim; apenas server-side |
| `APP_URL` | URL canónica, metadata, checkout e links de calendário/referral | sim; origem HTTPS aprovada |
| `SUPPORT_EMAIL` | página Ajuda e fallback dos contactos especializados | decisão do operador |
| `PARTNERSHIP_EMAIL` | página Equipa; usa `SUPPORT_EMAIL` se vazio | decisão do operador |
| `PRIVACY_EMAIL` | Política de Privacidade; usa `SUPPORT_EMAIL` se vazio | decisão legal |
| `LEGAL_EMAIL` | Termos; usa `SUPPORT_EMAIL` se vazio | decisão legal |
| `PARTNER_EMAIL_VENUES` | fallback de notificação dos leads de espaços | decisão operacional |
| `PARTNER_EMAIL_GUEST_MGMT` | fallback de notificação dos leads de convidados/bilhética | decisão operacional |
| `PARTNER_EMAIL_MUSIC` | fallback de notificação dos leads de música/animação | decisão operacional |
| `PARTNER_EMAIL_MARKETING` | fallback de notificação dos leads de marketing | decisão operacional |
| `STRIPE_SECRET_KEY` | criação de Checkout e reconciliação webhook | sim para pagamentos reais |
| `STRIPE_WEBHOOK_SECRET` | validação da assinatura webhook | sim para pagamentos reais |
| `PUBLIC_RATE_LIMIT_SECRET` | hashing dos identificadores do rate-limit público | recomendado; caso contrário usa a service role |
| `NEXT_PUBLIC_OAUTH_PROVIDERS` | botões OAuth (`google`, `apple`) | só para providers configurados |
| `RESEND_API_KEY` | Edge Function `send-email` | sim para email |
| `FROM_EMAIL` | remetente verificado da Edge Function `send-email` | sim para email |
| `ALLOWED_TEMPLATES` | allowlist da Edge Function `send-email` | sim para email |

Os quatro contactos públicos aceitam apenas um endereço simples, sem display name. Endereços ausentes ou reservados não são mostrados: a interface encaminha para `/ajuda`. `FROM_EMAIL` aceita o formato de remetente verificado pelo Resend.

O bootstrap da Vercel consome `VERCEL_PROJECT_ID`, `VERCEL_TEAM_ID`, `VERCEL_ENV_TARGETS`, `VERCEL_ENV_ALLOWLIST` e `VERCEL_PLAIN_ENV_KEYS` do ambiente ou de `.env.local`. `VERCEL_TOKEN` é aceite apenas no ambiente do processo. `VERCEL_SOURCE_ENV_FILE` pode apontar para outro ficheiro local. Nenhuma destas variáveis é um valor da aplicação.

## Decisões obrigatórias antes da produção

O repositório não escolhe estes valores pelo operador:

- domínio canónico e respetiva configuração DNS/TLS;
- identidade da entidade operadora, dados de registo, morada e revisão jurídica dos Termos/Privacidade;
- endereços de suporte, parcerias, privacidade e legal;
- domínio de email verificado, remetente e política de entrega;
- conta e modo Stripe, regras comerciais, reembolsos e responsáveis pela reconciliação;
- projetos/equipas de produção na Supabase e Vercel;
- providers OAuth e credenciais, caso sejam ativados;
- alertas, on-call e destino dos logs operacionais;
- ícones PWA quadrados aprovados.

## Ordem segura de deployment

1. Fechar as decisões acima, preparar backup/snapshot da base de dados e confirmar o plano de rollback.
2. Ligar a CLI Supabase ao projeto certo e rever as migrações antes de executar `pnpm dlx supabase db push`. A baseline Indigo out-of-band em `scripts/migrations/apply/` não pertence a este fluxo e segue exclusivamente o seu runbook. Nunca aplicar primeiro em produção sem ensaio num ambiente equivalente.
3. Configurar os segredos da Edge Function num ficheiro local não versionado contendo `RESEND_API_KEY`, `FROM_EMAIL` e `ALLOWED_TEMPLATES`; aplicar com `pnpm dlx supabase secrets set --env-file <ficheiro-local>`.
4. Publicar `send-email` com verificação JWT. Se o webhook escolhido for a Edge Function, publicar `stripe-webhook` sem verificação JWT; a própria função valida a assinatura Stripe.
5. Preencher em `.env.local` os identificadores de destino, a allowlist e os valores Vercel. Executar sem expor o token na linha de argumentos:

   ```bash
   VERCEL_TOKEN="$VERCEL_TOKEN" bash scripts/vercel-env-bootstrap.sh
   ```

6. Fazer deploy da aplicação, executar os smoke tests e só depois encaminhar tráfego/DNS.
7. Configurar exatamente um endpoint Stripe operacional: `/api/stripe/webhook` na aplicação ou `stripe-webhook` na Supabase. Subscrever apenas `checkout.session.completed` e `charge.refunded`. O segredo de assinatura tem de corresponder ao endpoint escolhido.

O RPC de reconciliação é idempotente, mas manter um único endpoint reduz duplicação operacional. Falhas de reconciliação devolvem erro para que o Stripe volte a entregar o evento.

## Bootstrap Vercel

O script só envia as chaves enumeradas em `VERCEL_ENV_ALLOWLIST`, exige IDs de projeto/equipa e targets explícitos, e falha se uma chave permitida estiver vazia. Chaves não listadas nunca são enviadas. `VERCEL_PLAIN_ENV_KEYS` seleciona as entradas públicas; as restantes são criadas como encrypted. O script não imprime valores, comprimentos, IDs ou payloads.

Não guardar `VERCEL_TOKEN` em `.env.local`. Rever a allowlist antes de cada execução; omitir variáveis opcionais vazias e remover manualmente na Vercel qualquer variável obsoleta que já exista. Os valores de Edge Functions pertencem aos secrets da Supabase e não à Vercel, salvo se passarem a ter um consumidor Next.js real.

## Gates de qualidade

Executar no mesmo commit que será publicado:

```bash
pnpm exec tsc --noEmit
node --test tests/*.test.mjs
bash -n scripts/vercel-env-bootstrap.sh
git diff --check
pnpm build
```

Depois do deploy, validar pelo menos `/`, `/catalogo`, `/ajuda`, `/privacidade`, `/termos`, `/api/health`, autenticação, publicação/candidatura, Checkout em modo de teste, replay de webhook e email transacional. Confirmar que os contactos e o hostname apresentados são os aprovados.

## Rollback

- Vercel: manter o deployment anterior e promovê-lo novamente se os smoke tests falharem.
- Edge Functions: voltar a publicar a versão do commit anterior e confirmar os respetivos secrets.
- Stripe: desativar o endpoint novo se estiver a falhar; não reutilizar o respetivo signing secret noutro endpoint.
- Base de dados: as migrações são forward-only. Restaurar o snapshot apenas com um plano aprovado ou criar uma migração corretiva ensaiada; não executar reset em produção.
- Após rollback, repetir health check, login, consulta de catálogo e reconciliação de pagamentos pendentes.

## Bloqueador PWA

O manifest não anuncia ícones enquanto não existirem assets quadrados/maskable aprovados (mínimo 192×192 e 512×512). Os wordmarks horizontais aprovados não devem ser redimensionados ou declarados como ícones quadrados. Instalação PWA completa fica bloqueada até o utilizador aprovar esses assets.
