# Production identity reconciliation runbook

Status: prepared locally and reported-unverified. Nothing in this runbook has
been executed against a live Supabase project.

This runbook applies only
`20260819094823_airfnb_identity_reconciliation.sql`. The captured target state
is:

- remote migration head: `20260815142342`
- retired UUID: `11111111-1111-1111-1111-111111111111`
- retired email: `seed@airfnb.local`
- preservation baseline: 12 owned catalogue services, 5 authored published
  articles, and 1 blog-author row
- captured history divergence: 45 local-only versions and 242 remote-only
  versions

The repository migration directory must never be used as the deployment
directory for this operation. Its divergent history can replay unrelated
migrations. Do not use `db push`, `migration repair`, or `--include-all`.

## Atomicity contract

Supabase CLI 2.115.0 executes each migration file in a per-file session but
does not supply an outer transaction around that file. This migration therefore
owns its atomicity: it has exactly one explicit `BEGIN`, one terminal `COMMIT`,
and bounded local `statement_timeout` and `lock_timeout` settings before any
precondition, lock, DDL, or DML. Any exception before the terminal commit aborts
the transaction, and the CLI session ending rolls back every migration-owned
guard, trigger, privilege, and data change.

Do not remove the explicit transaction control, relax either timeout, or wrap
the production command in a second transaction. The disposable runtime harness
contains no `COMMIT` and does not include the migration. Its driver starts a
separate `psql` session for each intentional failure, good apply, and good
reapply so an outer test transaction cannot mask candidate atomicity.

## Portable disposable-database proof

This is a local-only test. It must never receive a linked project, network host,
password, token, or live database. Start with the named cumulative temporary
source fixture: 41 public tables, predecessor guard present, exact detached
12/5 content, and no runtime Auth dependency tables or fixture identities.

Set the three values explicitly for the local PostgreSQL instance. The socket
must be an absolute local socket directory; the source database must be the
named temporary fixture. Run the command twice as two complete independent
executions:

```sh
LOCAL_SOCKET=/path/to/local/postgresql/socket
LOCAL_PORT=NNNNN
LOCAL_SOURCE_DB=temporary_fixture_database
bash scripts/test-identity-reconciliation.sh \
  --socket "$LOCAL_SOCKET" \
  --port "$LOCAL_PORT" \
  --source-db "$LOCAL_SOURCE_DB"
```

The driver generates and validates one
`fb_tailor_identity_runtime_<pid>_<nonce>` database name, refuses a pre-existing
target, clones only the explicitly named source, and drops only the database it
created in that invocation. Its exit trap verifies zero scratch residue. A
source fingerprint and zero-fixture audit run before and after the scratch test
and must match exactly.

Each execution must prove all of the following without an outer transaction:

- an intentional 11-of-12 drift reaches the guard DDL, fails the exact content
  precondition, and leaves the guard, privileges, Auth dependencies, and data
  fully rolled back;
- the exact good state completes a good apply and reapply while preserving the
  detached 12/5 content and every unrelated fixture;
- legitimate organizer/owner edits and trusted admin/staff paths still work,
  unauthorized privilege changes and retired-profile recreation return 42501,
  and `anon`/`authenticated` retain no direct function `EXECUTE` privilege;
- the final source fingerprint, zero-fixture audit, and scratch cleanup audit
  all pass.

Any failed marker, changed fingerprint, non-zero fixture count, or residual
scratch database is a stop condition. Do not point the driver at a different
database to make a failure pass and do not weaken the harness.

## Required gates

One operator performs the steps; a second operator records and confirms every
gate before application.

1. Target gate: record the project name and ref from the Supabase dashboard and
   compare the explicit ref with `supabase projects list`. Stop if they differ.
   Do not put a project ref, access token, or database password in this file or
   in shell history.
2. PITR gate: confirm Point-in-Time Recovery is enabled, record a recovery
   timestamp immediately before application, and confirm that the team knows
   how to restore it to a separate project. Stop if PITR or a tested backup is
   unavailable.
3. Change gate: freeze profile/identity administration for the window and
   confirm no operator is concurrently editing the retired identity or its
   catalogue/editorial rows.
4. Session gate: record the access-token maximum lifetime. Deleting the auth
   user removes database sessions and refresh tokens, but an already-issued JWT
   can remain usable until expiry. If immediate invalidation is required, stop
   and complete the currently supported Supabase session-revocation procedure
   before continuing. The migration's retired-UUID trigger prevents that JWT
   from recreating its profile, but it is not a claim of global JWT revocation.
5. History gate: the read-only migration list must show remote head
   `20260815142342`. Stop if the head differs. The isolated deployment bundle
   prepared below must show exactly one local-only version newer than the head:
   `20260819094823`. Stop if any other pending version appears.

## Build the isolated deployment bundle

Run from a clean checkout containing the reviewed migration. Use a disposable
directory so the 45 unrelated local-only migrations are not candidates:

```sh
DEPLOY_ROOT="$(mktemp -d)"
mkdir -p "$DEPLOY_ROOT/supabase/migrations"
cp supabase/config.toml.example "$DEPLOY_ROOT/supabase/config.toml"
cp supabase/migrations/20260819094823_airfnb_identity_reconciliation.sql \
  "$DEPLOY_ROOT/supabase/migrations/"
cd "$DEPLOY_ROOT"
```

Inspect `supabase/migrations` and verify it contains exactly the one SQL file.
Set `PROJECT_REF` interactively in the shell; never commit it. Run the
read-only history inspection:

```sh
SUPABASE_TELEMETRY_DISABLED=1 supabase migration list \
  --linked --project-ref "$PROJECT_REF"
```

Stop unless the last remote version is exactly `20260815142342` and the only
local-only version above it is `20260819094823`.

## Exact pre-application database check

Run this as one read-only query through the approved SQL console or CLI query
facility. It must return one row with `exact_identity=1`, `exact_profile=1`,
`owned_services=12`, `published_articles=5`, `blog_authors=1`,
`uuid_conflicts=0`, `email_conflicts=0`, `required_relations=24`, and
`nullable_history_columns=6`.

```sql
with required_relation(name) as (values
  ('auth.identities'), ('auth.mfa_factors'), ('auth.refresh_tokens'),
  ('auth.sessions'), ('auth.users'), ('public.airfnb_addresses'),
  ('public.airfnb_blog_authors'), ('public.airfnb_blog_posts'),
  ('public.airfnb_bookings'), ('public.airfnb_contact_requests'),
  ('public.airfnb_conversation_participants'),
  ('public.airfnb_event_requests'), ('public.airfnb_events'),
  ('public.airfnb_favorites'), ('public.airfnb_messages'),
  ('public.airfnb_notifications'), ('public.airfnb_organizer_reviews'),
  ('public.airfnb_partner_leads'), ('public.airfnb_platform_settings'),
  ('public.airfnb_profiles'), ('public.airfnb_proposals'),
  ('public.airfnb_request_invitations'), ('public.airfnb_reviews'),
  ('public.airfnb_trucks')
), nullable_history(table_name, column_name) as (values
  ('airfnb_bookings', 'organizer_id'),
  ('airfnb_messages', 'sender_id'),
  ('airfnb_reviews', 'organizer_id'),
  ('airfnb_proposals', 'prepared_by'),
  ('airfnb_contact_requests', 'handled_by'),
  ('airfnb_request_invitations', 'invited_by')
)
select
  (select count(*) from auth.users
    where id='11111111-1111-1111-1111-111111111111'::uuid
      and email='seed@airfnb.local') as exact_identity,
  (select count(*) from public.airfnb_profiles
    where id='11111111-1111-1111-1111-111111111111'::uuid) as exact_profile,
  (select count(*) from public.airfnb_trucks
    where owner_id='11111111-1111-1111-1111-111111111111'::uuid) as owned_services,
  (select count(*) from public.airfnb_blog_posts
    where author_id='11111111-1111-1111-1111-111111111111'::uuid
      and status='published') as published_articles,
  (select count(*) from public.airfnb_blog_authors
    where id='11111111-1111-1111-1111-111111111111'::uuid) as blog_authors,
  (select count(*) from auth.users
    where id='11111111-1111-1111-1111-111111111111'::uuid
      and email is distinct from 'seed@airfnb.local') as uuid_conflicts,
  (select count(*) from auth.users
    where lower(email)=lower('seed@airfnb.local')
      and (id<>'11111111-1111-1111-1111-111111111111'::uuid
        or email is distinct from 'seed@airfnb.local')) as email_conflicts,
  (select count(*) from required_relation
    where to_regclass(name) is not null) as required_relations,
  (select count(*) from nullable_history expected
    join information_schema.columns actual
      on actual.table_schema='public'
     and actual.table_name=expected.table_name
     and actual.column_name=expected.column_name
     and actual.is_nullable='YES') as nullable_history_columns;
```

Any different value is a stop condition. Do not edit the migration to fit an
uninvestigated live state.

## Apply

From the isolated deployment directory, this is the only approved mutating
command:

```sh
SUPABASE_TELEMETRY_DISABLED=1 supabase migration up \
  --linked --project-ref "$PROJECT_REF"
```

Do not add any flags. In particular, never add the all-history inclusion flag.
Capture the command's exit status and output in the change record without
copying credentials.

## Exact post-application checks

First rerun the read-only migration list. The remote head must now be exactly
`20260819094823`, with no other newly applied version.

Then run the following query. Every boolean must be `true`; the two content
counts must be 12 and 5, and all four auth-dependency counts must be zero.

```sql
select
  not exists (
    select 1 from auth.users
     where id='11111111-1111-1111-1111-111111111111'::uuid
        or lower(email)=lower('seed@airfnb.local')
  ) as identity_absent,
  not exists (
    select 1 from public.airfnb_profiles
     where id='11111111-1111-1111-1111-111111111111'::uuid
  ) as profile_absent,
  (select count(*) from public.airfnb_trucks
    where slug in (
      'bbq-kings','creperia-pt','divine-burguers','el-mexicano',
      'gypsy-kitchen','la-dolce-vita','pizza-vesuvio',
      'portuguese-tradition','sushi-zen','taco-fiesta',
      'turkish-delights','wok-and-roll'
    ) and owner_id is null) as detached_services,
  (select count(*) from public.airfnb_blog_posts
    where slug in (
      'casamentos-food-trucks-5-dicas',
      'como-organizar-evento-perfeito-food-trucks',
      'festivais-2025-o-que-ai-vem',
      'quanto-custa-catering-50-pessoas',
      'tendencias-gastronomicas-2025'
    ) and author_id is null and status='published') as detached_articles,
  to_regprocedure('public.airfnb_guard_profile_role()') is not null as guard_present,
  exists (
    select 1 from pg_trigger
     where tgrelid='public.airfnb_profiles'::regclass
       and tgname='airfnb_profiles_guard_role'
       and tgenabled<>'D'
  ) as trigger_enabled,
  not has_function_privilege(
    'anon', 'public.airfnb_guard_profile_role()', 'EXECUTE'
  ) as anon_execute_revoked,
  not has_function_privilege(
    'authenticated', 'public.airfnb_guard_profile_role()', 'EXECUTE'
  ) as authenticated_execute_revoked,
  (select count(*) from auth.sessions
    where user_id::text='11111111-1111-1111-1111-111111111111') as sessions,
  (select count(*) from auth.refresh_tokens
    where user_id::text='11111111-1111-1111-1111-111111111111') as refresh_tokens,
  (select count(*) from auth.identities
    where user_id::text='11111111-1111-1111-1111-111111111111') as identities,
  (select count(*) from auth.mfa_factors
    where user_id::text='11111111-1111-1111-1111-111111111111') as mfa_factors;
```

Finally, run the same fail-closed UUID sweep used by the migration. A successful
check returns `DO`; any remaining occurrence raises an exception naming the
escaped schema, table, and column.

```sql
do $uuid_sweep$
declare
  retired_id constant uuid := '11111111-1111-1111-1111-111111111111';
  uuid_column record;
  matches bigint;
begin
  for uuid_column in
    select namespace.nspname as schema_name,
           relation.relname as table_name,
           attribute.attname as column_name
      from pg_catalog.pg_attribute as attribute
      join pg_catalog.pg_class as relation
        on relation.oid=attribute.attrelid
      join pg_catalog.pg_namespace as namespace
        on namespace.oid=relation.relnamespace
     where namespace.nspname='public'
       and relation.relkind in ('r','p')
       and attribute.attnum>0
       and not attribute.attisdropped
       and attribute.atttypid='uuid'::pg_catalog.regtype
  loop
    execute format(
      'select count(*) from %I.%I where %I=$1',
      uuid_column.schema_name,
      uuid_column.table_name,
      uuid_column.column_name
    ) into matches using retired_id;
    if matches<>0 then
      raise exception 'retired UUID remains in %.%.%',
        uuid_column.schema_name,
        uuid_column.table_name,
        uuid_column.column_name;
    end if;
  end loop;
end
$uuid_sweep$;
```

Also verify through normal application paths that an organizer and owner can
edit ordinary profile fields and switch between organizer/owner, cannot assign
admin/staff, and an existing trusted admin/staff operator can still manage a
legitimate account. Never use the retired UUID or email as a test account.

## Stop conditions and recovery

Stop immediately on any precondition error, unexpected pending migration,
history-head mismatch, content count mismatch, schema/nullability drift,
non-zero postcondition, or role-control failure. Do not retry with weaker SQL.

If application fails before commit, preserve the error and verify the remote
ledger did not advance; the migration transaction should have rolled back. If
the ledger advanced or a post-check fails, stop application writes and recover
from the recorded PITR point according to the incident plan. Do not use history
repair as rollback.

If administrative access must be recovered, create a new legitimate identity
through the approved Auth Admin workflow and have an existing trusted
admin/staff operator assign its database-backed role. Never recreate, remap, or
restore the retired UUID/email credential, even during recovery.
