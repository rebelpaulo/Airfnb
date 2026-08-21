# Baseline F&B no projeto Supabase Indigo partilhado

Este procedimento instala a baseline F&B Tailor no projeto Indigo partilhado sem importar, criar, alterar ou apagar identidades Supabase Auth. A operação remota não faz parte da preparação local deste artefacto e exige autorização separada.

## Identidade imutável

- Origem F&B observada: `rvcvyeodglovmptcuyiz`.
- Destino Indigo: `tzwpezkbljqkgnzhazeo`.
- Baseline out-of-band: `scripts/migrations/apply/20260821124724_indigo_shared_project_baseline.sql`.
- Rollback seletivo: `scripts/migrations/rollback/20260821124724_indigo_shared_project_baseline.sql`.
- Predecessor Indigo obrigatório: exatamente 85 versões, última `20260821171040`, MD5 da lista ordenada `1f0eebdf3bcee57d873c3d4f87f260a9`.
- Estado observado antes da operação: zero objetos, políticas, buckets, jobs ou membros Realtime com prefixo `airfnb`; duas identidades F&B já existem no Auth do destino.

Qualquer diferença nestes identificadores é `STOP`. Não adaptar hashes, contagens ou nomes durante a janela de mudança.

## 1. Preflight remoto somente de leitura

Guardar a saída integral das consultas e executá-las com uma sessão administrativa ligada explicitamente ao destino. Confirmar primeiro `select current_database(), current_user;` e a referência do projeto no Dashboard.

```sql
select count(*) as versions,
       max(version) as latest,
       md5(string_agg(version, ',' order by version)) as ordered_versions_md5
from supabase_migrations.schema_migrations;

select name, default_version, installed_version
from pg_available_extensions
where name in ('pgcrypto','pg_trgm','unaccent','postgis','pg_cron')
order by name;

select 'relations' as kind, count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'airfnb_%'
union all select 'functions',count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'airfnb_%'
union all select 'public policies',count(*) from pg_policies where schemaname='public' and policyname like 'airfnb_%'
union all select 'storage policies',count(*) from pg_policies where schemaname='storage' and policyname like 'airfnb_%'
union all select 'buckets',count(*) from storage.buckets where id like 'airfnb-%'
union all select 'Realtime members',count(*) from pg_publication_tables where pubname='supabase_realtime' and tablename like 'airfnb_%';

select count(*) as auth_users,
       md5(string_agg(id::text || ':' || coalesce(email,''), ',' order by id)) as auth_identity_digest
from auth.users;
```

Esperado para extensões antes da primeira aplicação: `pgcrypto` instalada; `pg_trgm`, `unaccent`, `postgis` e `pg_cron` disponíveis, mesmo que ainda não instaladas. A baseline cria as quatro extensões disponíveis dentro da mesma transação, depois de validar história e colisões, e só depois bloqueia/usa `cron.job`. Se alguma não estiver disponível, é `STOP`.

O `cron.job` pode não existir antes da baseline porque nasce com `pg_cron`; não o consultar antes de confirmar que a extensão está instalada. A baseline faz esta ordenação internamente.

## 2. Backup e prova de recuperação

Confirmar primeiro um backup físico Supabase com estado `COMPLETED`, feito no próprio dia da janela, e registar o seu ID, timestamp, região e estado de PITR. Como o Indigo é partilhado, um restore total é apenas recuperação de último recurso: reverteria também escritas legítimas dos outros produtos posteriores ao backup. O rollback operacional normal continua a ser o rollback lógico seletivo da secção 5.

Quando existir acesso seguro à base, acrescentar também um backup lógico para reduzir o RPO. Criar um diretório novo, restrito e fora do repositório. Não colocar passwords na linha de comandos nem em ficheiros versionados.

```bash
umask 077
pg_dump "$INDIGO_DATABASE_URL" --format=custom --no-owner --file="$BACKUP_DIR/indigo-before-fb.dump"
pg_dump "$INDIGO_DATABASE_URL" --format=plain --schema=auth --data-only --no-owner --file="$BACKUP_DIR/indigo-auth-before.sql"
shasum -a 256 "$BACKUP_DIR/indigo-before-fb.dump" "$BACKUP_DIR/indigo-auth-before.sql"
pg_restore --list "$BACKUP_DIR/indigo-before-fb.dump" > "$BACKUP_DIR/indigo-before-fb.list"
```

Se o backup lógico for criado, confirmar que os ficheiros têm tamanho não nulo, guardar hashes e testar `pg_restore --list`. Se não for possível criá-lo sem expor credenciais ou PII, registar essa limitação e exigir simultaneamente: backup físico `COMPLETED` no próprio dia, ensaio aprovado numa branch/clone, transação atómica e rollback seletivo validado. A recuperação integral de qualquer backup é uma operação separada e destrutiva; não a executar como rollback normal.

## 3. Aplicação explícita

Usar o ficheiro único diretamente com `psql`; não usar `supabase db push` sobre a cadeia histórica. `db push` tentaria reconciliar migrations F&B antigas com a história Indigo e não representa este merge controlado. Também não aplicar outra migration antes ou durante esta janela.

```bash
psql "$INDIGO_DATABASE_URL" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --file=scripts/migrations/apply/20260821124724_indigo_shared_project_baseline.sql
```

O ficheiro está deliberadamente fora de `supabase/migrations`: é um instalador out-of-band e nunca pode ser consumido por `supabase db push`. Contém `BEGIN/COMMIT`, timeouts locais, preflight exato, instalação transacional das extensões, locks de Storage/cron, instalação F&B e pós-condições. Uma falha aborta a transação inteira. A história `supabase_migrations.schema_migrations` permanece nas 85 versões Indigo; o estado desta baseline é selado em `public.airfnb_baseline_manifest`.

## 4. Pós-condições

Executar `tests/indigo-shared-project-baseline-runtime.sql` com `psql --set=ON_ERROR_STOP=1 --file=...` e guardar a saída. Além disso, repetir o preflight de Auth e comparar exatamente `auth_users` e `auth_identity_digest` com os valores anteriores.

Manifesto esperado:

- 169 relações `public.airfnb_%` (43 tabelas regulares no total, incluindo `airfnb_membership_tombstones` e o manifesto, além de sequências, índices e vistas);
- 24 enums/domínios, 68 funções, 67 políticas públicas e 20 triggers F&B;
- zero triggers F&B em `auth.users`;
- `airfnb_membership_tombstones` com RLS ativa, zero políticas e zero privilégios para `anon`, `authenticated` e `service_role`; esta tabela é o marcador de eliminação permanente da membership F&B, sem apagar a identidade em `auth.users`;
- 12 políticas Storage e 5 buckets `airfnb-*` com configuração exata;
- 2 jobs `airfnb_*` e 6 tabelas na publicação `supabase_realtime`;
- hashes `catalog_hash` e `storage_hash` selados e não nulos;
- exatamente 101 registos seed nas dez tabelas de catálogo/demo, com `seed_count` e `seed_hash` selados (104 registos contando também manifesto e dois jobs);
- as cinco extensões requeridas instaladas.
- os `DEFAULT PRIVILEGES` do projeto não podem alargar a API F&B: o manifesto tem RLS ativa, zero privilégios para `anon`, `authenticated` e `service_role`, nenhuma função F&B concede `EXECUTE` a `PUBLIC`, e a allowlist efetiva contém exatamente 7 grants `anon`, 43 `authenticated` e 11 `service_role`;
- `airfnb_assign_ics_token`, `airfnb_event_request_visibility_sync`, `airfnb_make_ics_token` e `airfnb_platform_settings_touch` têm `search_path` fixo.

Na aplicação, a eliminação de membership passa apenas por `POST /api/me/fb-membership`: valida origem e sessão, remove via Storage API os prefixos do avatar e dos serviços antes da mutação SQL, chama `airfnb_self_delete`, volta a remover/verificar os mesmos prefixos e só então confirma sucesso. A tombstone conserva os UUID técnicos dos serviços para que uma falha de Storage seja repetível; as políticas de escrita exigem um perfil F&B vivo e bloqueiam novos uploads depois da tombstone.

Executar novamente o mesmo ficheiro de baseline. O segundo resultado deve ser sucesso sem alterações de manifesto, Auth, história, objetos, buckets, jobs ou Realtime.

## 5. Rollback seletivo

Antes do rollback, confirmar que nenhum bucket `airfnb-*` contém objetos e que não existe drift do `catalog_hash`, de buckets ou de políticas. Fazer backup de dados F&B que tenham surgido depois da instalação; o rollback elimina as 43 tabelas F&B, incluindo o marcador `airfnb_membership_tombstones`, e todos os dados F&B.

```bash
psql "$INDIGO_DATABASE_URL" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --file=scripts/migrations/rollback/20260821124724_indigo_shared_project_baseline.sql
```

O rollback recalcula e compara o `catalog_hash` v1 antes de qualquer remoção, recusa drift de catálogo, Storage ou jobs e remove policies/triggers públicas apenas quando a relação pertence ao allowlist exato das 43 tabelas F&B. Remove também os 5 buckets, os 2 jobs e as 6 memberships Realtime conhecidas, e não usa `CASCADE`. Uma policy ou trigger com nome `airfnb` numa relação não-F&B faz a operação falhar atomicamente e nunca é apagada; uma dependência não-F&B tem o mesmo comportamento fail-closed.

As extensões `pg_trgm`, `unaccent`, `postgis` e `pg_cron` ficam deliberadamente instaladas: são capacidades globais do projeto partilhado, a sua proveniência/ausência de outros consumidores não pode ser provada com segurança, e removê-las não é rollback F&B seletivo. Registar este resíduo global. Não remover extensões sem uma análise separada de dependências e autorização explícita.

Depois do rollback, exigir zero resíduos F&B owned em relações, tipos, funções, políticas, triggers, buckets, jobs e Realtime; exigir exatamente o mesmo `auth_users` e digest Auth registados antes da aplicação, as mesmas 85 versões Indigo e as sentinelas Indigo intactas. Nem a aplicação, nem `airfnb_self_delete`, nem o rollback apagam ou alteram identidades Supabase Auth.

## Critérios de STOP

Parar sem aplicar ou sem tentar “corrigir no momento” quando ocorrer qualquer um destes casos:

- referência do destino, contagem/última versão/hash da história, ou digest Auth divergente;
- qualquer colisão `airfnb` antes da primeira aplicação;
- extensão requerida indisponível ou falha de instalação transacional;
- lock timeout, statement timeout, erro de catálogo, `catalog_hash`/hash de manifesto divergente ou pós-condição falhada;
- tentativa de criar trigger em `auth.users`, importar Auth ou alterar as duas identidades existentes;
- objetos dentro de buckets F&B, drift Storage/jobs, ou dependência não-F&B durante rollback;
- backup físico ausente/não concluído no próprio dia; ou, quando foi criado backup lógico, ficheiro sem hash/ilegível por `pg_restore --list`; ou operador sem autorização explícita.

Perante `STOP`, preservar logs e hashes, não usar `db push`, não editar a migration aplicada e escalar para uma nova análise read-only.
