#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf '%s\n' 'usage: test-local-e2e-go-live.sh --socket DIR --port PORT --source-db DB --stripe-sha256 SHA --follower-sha256 SHA' >&2
  exit 64
}

socket_directory=''
postgres_port=''
source_database=''
stripe_sha256=''
follower_sha256=''
while (($#)); do
  case "$1" in
    --socket) (($# >= 2)) || usage; socket_directory="$2"; shift 2 ;;
    --port) (($# >= 2)) || usage; postgres_port="$2"; shift 2 ;;
    --source-db) (($# >= 2)) || usage; source_database="$2"; shift 2 ;;
    --stripe-sha256) (($# >= 2)) || usage; stripe_sha256="$2"; shift 2 ;;
    --follower-sha256) (($# >= 2)) || usage; follower_sha256="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -d "$socket_directory" ]] || usage
[[ "$postgres_port" =~ ^[0-9]{2,5}$ ]] || usage
[[ "$source_database" =~ ^[a-z][a-z0-9_]{0,62}$ ]] || usage
[[ "$stripe_sha256" =~ ^[0-9a-f]{64}$ && "$follower_sha256" =~ ^[0-9a-f]{64}$ ]] || usage

readonly EXPECTED_STRIPE='5c244501a3f2e7b9d5aef6fa9d40b48a101b3efe0221401e9c6207d03f927591'
readonly EXPECTED_FOLLOWER='2fdd44ad5d0da55119a867b0aafc124cd3ffa5b963904656363cccd26c366e92'
[[ "$stripe_sha256" == "$EXPECTED_STRIPE" && "$follower_sha256" == "$EXPECTED_FOLLOWER" ]] || {
  printf '%s\n' 'verified dependency hashes refused' >&2
  exit 65
}

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly stripe_file="$repository_root/supabase/migrations/20260820155322_stripe_canonical_reconciliation.sql"
readonly follower_file="$repository_root/supabase/migrations/20260820230518_supplier_acl_caller_reconciliation.sql"
readonly identity_file="$repository_root/supabase/migrations/20260819094823_airfnb_identity_reconciliation.sql"
readonly identity_runtime_file="$repository_root/tests/identity-reconciliation-runtime.sql"
readonly runtime_integrity_file="$repository_root/supabase/migrations/20260820152018_airfnb_runtime_function_integrity_reconciliation.sql"
readonly privacy_file="$repository_root/supabase/migrations/20260820153725_public_event_request_privacy_reconciliation.sql"
readonly messaging_file="$repository_root/supabase/migrations/20260820154054_messaging_reviews_reconciliation.sql"
readonly storage_file="$repository_root/supabase/migrations/20260820154100_storage_abuse_reconciliation.sql"
readonly catalog_file="$repository_root/supabase/migrations/20260820154104_catalog_service_types_reconciliation.sql"
readonly marketplace_file="$repository_root/supabase/migrations/20260820154358_marketplace_workflow_reconciliation.sql"
readonly fixture_server="$repository_root/scripts/local-e2e-supabase-fixture.mjs"
readonly seed_file="$repository_root/tests/fixtures/local-e2e-seed.sql"
readonly source_test="$repository_root/tests/local-e2e-go-live-source.test.mjs"
readonly driver_file="$repository_root/scripts/test-local-e2e-go-live.sh"
readonly PSQL='/opt/homebrew/bin/psql'
readonly PG_DUMP='/opt/homebrew/bin/pg_dump'
readonly CREATEDB='/opt/homebrew/bin/createdb'
readonly DROPDB='/opt/homebrew/bin/dropdb'
readonly AGENT_BROWSER='/opt/homebrew/bin/agent-browser'
readonly NODE='/opt/homebrew/bin/node'
readonly PNPM='/usr/local/bin/pnpm'

sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }
sha256_stream() { shasum -a 256 | awk '{print $1}'; }

[[ "$(sha256_file "$stripe_file")" == "$stripe_sha256" && "$(sha256_file "$follower_file")" == "$follower_sha256" ]] || {
  printf '%s\n' 'dependency artifact hash mismatch' >&2
  exit 65
}

psql_source=("$PSQL" -X --no-psqlrc --host="$socket_directory" --port="$postgres_port" --dbname="$source_database" --set=ON_ERROR_STOP=1 --quiet)
[[ "$(PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" --tuples-only --no-align --command='select current_database();')" == "$source_database" ]] || {
  printf '%s\n' 'source database connection mismatch' >&2
  exit 65
}

source_fingerprint() {
  PGOPTIONS='-c default_transaction_read_only=on' "$PG_DUMP" --host="$socket_directory" --port="$postgres_port" \
    --dbname="$source_database" --format=plain --schema=auth --schema=public --schema=storage --no-owner \
    | sed '/^\\restrict /d; /^\\unrestrict /d' | sha256_stream
}

readonly source_sha256_before="$(source_fingerprint)"
[[ "$source_sha256_before" == '65559343e7ffdf3795e1267425c5c6693ea79be56ef0d45ac43c39233e8b99dd' ]] || {
  printf 'source database fingerprint mismatch: %s\n' "$source_sha256_before" >&2
  exit 65
}

readonly temporary_directory="$(mktemp -d /private/tmp/fb-tailor-e2e.XXXXXX)"
readonly scratch_database="fb_tailor_e2e_${$}_${RANDOM}"
readonly identity_database="fb_tailor_identity_runtime_${$}_${RANDOM}"
readonly fixture_port="$((41000 + ($$ % 1000)))"
readonly app_port="$((43000 + ($$ % 1000)))"
readonly app_origin="http://127.0.0.1:${app_port}"
readonly fixture_origin="http://127.0.0.1:${fixture_port}"
readonly evidence_directory="$(mktemp -d /private/tmp/fb-tailor-e2e-evidence-${$}.XXXXXX)"
chmod 700 "$evidence_directory"
readonly credentials_file="$temporary_directory/credentials.json"
readonly request_log="$evidence_directory/requests.jsonl"
readonly fixture_stdout="$temporary_directory/fixture.stdout"
readonly fixture_stderr="$temporary_directory/fixture.stderr"
readonly app_stdout="$temporary_directory/app.stdout"
readonly app_stderr="$temporary_directory/app.stderr"
readonly dev_browser_directory="$evidence_directory/browser-dev"
readonly prod_browser_directory="$evidence_directory/browser-prod"
browser_directory="$dev_browser_directory"
browser_phase='dev'
readonly app_root="$temporary_directory/app-root"
mkdir -m 700 "$dev_browser_directory"
mkdir -m 700 "$prod_browser_directory"
mkdir -m 700 "$app_root"
for project_path in app components lib public types middleware.ts next.config.mjs package.json tsconfig.json next-env.d.ts; do
  [[ -e "$repository_root/$project_path" ]] || { printf 'required app path missing: %s\n' "$project_path" >&2; exit 65; }
  cp -R "$repository_root/$project_path" "$app_root/$project_path"
done
[[ -d "$repository_root/node_modules" ]] || { printf '%s\n' 'required app path missing: node_modules' >&2; exit 65; }
ln -s "$repository_root/node_modules" "$app_root/node_modules"

[[ "$scratch_database" =~ ^fb_tailor_e2e_[0-9]+_[0-9]+$ && "$identity_database" =~ ^fb_tailor_identity_runtime_[0-9]+_[0-9]+$ ]] || exit 65
fixture_pid=''
app_pid=''
browser_sessions=''

database_count() {
  [[ "$1" =~ ^fb_tailor_(e2e|identity_runtime)_[0-9]+_[0-9]+$ ]] || return 65
  PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" --tuples-only --no-align \
    --command="select count(*) from pg_catalog.pg_database where datname = '$1';"
}

cleanup() {
  local status=$?
  set +e
  for session in $browser_sessions; do "$AGENT_BROWSER" --session "$session" close >/dev/null 2>&1; done
  if [[ -n "$app_pid" ]]; then kill -TERM "$app_pid" 2>/dev/null; wait "$app_pid" 2>/dev/null; fi
  if [[ -n "$fixture_pid" ]]; then kill -TERM "$fixture_pid" 2>/dev/null; wait "$fixture_pid" 2>/dev/null; fi
  if [[ "$(database_count "$scratch_database" 2>/dev/null)" == 1 ]]; then
    "$PSQL" -X --no-psqlrc --host="$socket_directory" --port="$postgres_port" --dbname=template1 --set=ON_ERROR_STOP=1 --quiet \
      --command="select pg_catalog.pg_terminate_backend(pid) from pg_catalog.pg_stat_activity where datname = '$scratch_database' and pid <> pg_backend_pid();" >/dev/null 2>&1
    "$DROPDB" --host="$socket_directory" --port="$postgres_port" --maintenance-db=template1 -- "$scratch_database" >/dev/null 2>&1
  fi
  if [[ "$(database_count "$identity_database" 2>/dev/null)" == 1 ]]; then
    "$DROPDB" --host="$socket_directory" --port="$postgres_port" --maintenance-db=template1 -- "$identity_database" >/dev/null 2>&1
  fi
  # Credentials are ephemeral runtime material, never diagnostic evidence.
  [[ -f "$credentials_file" ]] && rm -f -- "$credentials_file"
  if ((status == 0)); then
    find "$temporary_directory" -type f -delete
    find "$temporary_directory" -depth -type d -empty -delete
  else
    printf 'LOCAL_E2E_DIAGNOSTICS=%s\nLOCAL_E2E_EVIDENCE=%s\n' "$temporary_directory" "$evidence_directory" >&2
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

[[ "$(database_count "$scratch_database")" == 0 && "$(database_count "$identity_database")" == 0 ]] || exit 65
"$CREATEDB" --host="$socket_directory" --port="$postgres_port" --maintenance-db=template1 --template="$source_database" -- "$identity_database"
psql_identity=("$PSQL" -X --no-psqlrc --host="$socket_directory" --port="$postgres_port" --dbname="$identity_database" --set=ON_ERROR_STOP=1 --quiet)
"${psql_identity[@]}" --set=identity_runtime_database="$identity_database" --set=identity_runtime_phase=setup_drift --file="$identity_runtime_file" >/dev/null
if "${psql_identity[@]}" --file="$identity_file" >"$temporary_directory/identity-expected-failure.log" 2>&1; then
  printf '%s\n' 'identity drift unexpectedly accepted' >&2
  exit 1
fi
grep -Fq 'identity reconciliation refused: expected exactly the 12 observed catalogue services' "$temporary_directory/identity-expected-failure.log" || {
  printf '%s\n' 'identity predecessor failed unexpectedly' >&2
  exit 1
}
"${psql_identity[@]}" --set=identity_runtime_database="$identity_database" --set=identity_runtime_phase=assert_failed_atomicity_and_prepare_good --file="$identity_runtime_file" >/dev/null
"${psql_identity[@]}" --file="$identity_file" >/dev/null
"${psql_identity[@]}" --set=identity_runtime_database="$identity_database" --set=identity_runtime_phase=assert_good --file="$identity_runtime_file" >/dev/null
"${psql_identity[@]}" >/dev/null <<'SQL'
delete from public.airfnb_trucks where slug = 'identity-runtime-unrelated-service';
delete from public.airfnb_blog_posts where slug = 'identity-runtime-unrelated-article';
delete from public.airfnb_blog_authors where id = '99999999-9999-9999-9999-999999999999';
delete from auth.users where id in (
  '22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333',
  '44444444-4444-4444-4444-444444444444', '55555555-5555-5555-5555-555555555555',
  '66666666-6666-6666-6666-666666666666', '77777777-7777-7777-7777-777777777777',
  '88888888-8888-8888-8888-888888888888', '99999999-9999-9999-9999-999999999999'
);
drop schema identity_runtime cascade;
SQL
"$PSQL" -X --no-psqlrc --host="$socket_directory" --port="$postgres_port" --dbname="$source_database" --set=ON_ERROR_STOP=1 --quiet \
  --command="alter database \"$identity_database\" rename to \"$scratch_database\";"
psql_scratch=("$PSQL" -X --no-psqlrc --host="$socket_directory" --port="$postgres_port" --dbname="$scratch_database" --set=ON_ERROR_STOP=1 --quiet)
for migration in \
  "$runtime_integrity_file" "$privacy_file" "$messaging_file" \
  "$storage_file" "$catalog_file" "$marketplace_file" "$stripe_file" "$follower_file"; do
  "${psql_scratch[@]}" --file="$migration" >/dev/null
done
"${psql_scratch[@]}" --file="$seed_file"

fixture_object_check="$("${psql_scratch[@]}" --tuples-only --no-align --field-separator=':' --command="select
  to_regprocedure('public.airfnb_reconcile_stripe_event(text,text,timestamptz,uuid,uuid,uuid,text,bigint,text,text,bigint)') is not null,
  to_regprocedure('public.airfnb_supplier_services(uuid)') is not null,
  to_regprocedure('public.airfnb_supplier_lock_fee(uuid)') is not null,
  (select count(*) from auth.users where id::text like 'f2700000-0000-4000-8000-%');")"
[[ "$fixture_object_check" == 't:t:t:4' ]] || { printf 'fixture final-chain check failed: %s\n' "$fixture_object_check" >&2; exit 1; }
printf 'LOCAL_E2E_SOURCE_AND_SEED_PASS fingerprint=%s actors=4\n' "$source_sha256_before"

"$NODE" "$fixture_server" \
  --socket "$socket_directory" --port "$postgres_port" --database "$scratch_database" \
  --listen-port "$fixture_port" --app-origin "$app_origin" \
  --credentials-file "$credentials_file" --request-log "$request_log" \
  >"$fixture_stdout" 2>"$fixture_stderr" &
fixture_pid=$!

for _ in {1..80}; do
  if curl --noproxy '*' --fail --silent "$fixture_origin/health" >/dev/null 2>&1; then break; fi
  kill -0 "$fixture_pid" 2>/dev/null || { sed -n '1,80p' "$fixture_stderr" >&2; exit 1; }
  sleep 0.1
done
curl --noproxy '*' --fail --silent "$fixture_origin/health" >/dev/null
[[ -s "$credentials_file" && "$(stat -f '%Lp' "$credentials_file")" == 600 ]] || { printf '%s\n' 'credential file contract failed' >&2; exit 1; }

read_credential() {
  "$NODE" -e 'const fs=require("node:fs"); const value=process.argv[2].split(".").reduce((o,k)=>o?.[k],JSON.parse(fs.readFileSync(process.argv[1],"utf8"))); if(typeof value!=="string") process.exit(2); process.stdout.write(value);' "$credentials_file" "$1"
}
anon_key="$(read_credential anon_key)"
service_key="$(read_credential service_role_key)"
fixture_password="$(read_credential password)"
organizer_email="$(read_credential actors.organizer.email)"
supplier_a_email="$(read_credential actors.supplier_a.email)"
supplier_b_email="$(read_credential actors.supplier_b.email)"
admin_email="$(read_credential actors.admin.email)"
signup_email="$(read_credential signup_email)"

[[ "$fixture_origin" == http://127.0.0.1:* && "$app_origin" == http://127.0.0.1:* ]] || exit 65

(
  cd "$app_root"
  exec env -i \
    PATH='/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin' LANG='C' LC_ALL='C' TMPDIR='/private/tmp' \
    NODE_ENV='development' NEXT_TELEMETRY_DISABLED='1' \
    NEXT_PUBLIC_SUPABASE_URL="$fixture_origin" NEXT_PUBLIC_SUPABASE_ANON_KEY="$anon_key" \
    SUPABASE_SERVICE_ROLE_KEY="$service_key" APP_URL="$app_origin" \
    NEXT_PUBLIC_OAUTH_PROVIDERS='' ENABLE_DEV_PAY='1' \
    "$repository_root/node_modules/.bin/next" dev -H 127.0.0.1 -p "$app_port"
) >"$app_stdout" 2>"$app_stderr" &
app_pid=$!

for _ in {1..240}; do
  if curl --noproxy '*' --fail --silent "$app_origin/" >/dev/null 2>&1; then break; fi
  kill -0 "$app_pid" 2>/dev/null || { sed -n '1,100p' "$app_stderr" >&2; exit 1; }
  sleep 0.25
done
curl --noproxy '*' --fail --silent "$app_origin/" >/dev/null
printf 'LOCAL_E2E_LOOPBACK_SERVERS_PASS fixture=%s app=%s\n' "$fixture_origin" "$app_origin"

ab() { local session="$1"; shift; "$AGENT_BROWSER" --session "$session" --screenshot-dir "$browser_directory" "$@"; }
submit_same_origin_logout() {
  local session="$1" prepared
  prepared="$(ab "$session" eval '(() => {
    document.querySelector("#local-e2e-logout-post")?.remove();
    const form = document.createElement("form");
    form.id = "local-e2e-logout-post";
    form.method = "post";
    form.action = `${window.location.origin}/logout`;
    const button = document.createElement("button");
    button.type = "submit";
    button.textContent = "logout";
    form.appendChild(button);
    document.body.appendChild(form);
    return form.action === `${window.location.origin}/logout` ? "LOGOUT_POST_READY" : "LOGOUT_POST_REFUSED";
  })()')"
  [[ "$prepared" == *LOGOUT_POST_READY* ]] || { printf 'same-origin logout form refused state=%s\n' "$prepared" >&2; return 1; }
  # A native same-origin POST makes Chromium emit Origin and
  # Sec-Fetch-Site: same-origin, apply Set-Cookie, and follow the route's 303.
  ab "$session" click '#local-e2e-logout-post button[type="submit"]' >/dev/null
  ab "$session" wait 800 >/dev/null
}
redact_network_json() {
  "$NODE" -e 'let raw=""; process.stdin.setEncoding("utf8"); process.stdin.on("data",(chunk)=>raw+=chunk); process.stdin.on("end",()=>{ const value=JSON.parse(raw); const secrets=new Set(["apikey","authorization","cookie","set-cookie"]); const visit=(node)=>{ if(Array.isArray(node)) return node.forEach(visit); if(!node||typeof node!=="object") return; for(const [key,child] of Object.entries(node)){ if(secrets.has(key.toLowerCase())) node[key]="[REDACTED]"; else visit(child); } }; visit(value); process.stdout.write(JSON.stringify(value)); });'
}
assert_browser_diagnostics() {
  local console_file="$1" errors_file="$2" phase="$3"
  "$NODE" -e '
    const fs = require("node:fs");
    const [consolePath, errorsPath, phase] = process.argv.slice(1);
    const consoleEnvelope = JSON.parse(fs.readFileSync(consolePath, "utf8"));
    const errorsEnvelope = JSON.parse(fs.readFileSync(errorsPath, "utf8"));
    if (consoleEnvelope?.success !== true || !Array.isArray(consoleEnvelope?.data?.messages)) process.exit(21);
    if (errorsEnvelope?.success !== true || !Array.isArray(errorsEnvelope?.data?.errors)) process.exit(22);
    if (errorsEnvelope.data.errors.length !== 0) process.exit(23);
    const allowedDevWarnings = [
      /^Detected `scroll-behavior: smooth` on the `<html>` element\./,
      /^Image with src "\/truck-placeholder\.png" was detected as the Largest Contentful Paint \(LCP\)\./,
    ];
    const bad = consoleEnvelope.data.messages.filter((message) => {
      const type = String(message?.type ?? "").toLowerCase();
      if (type === "error") return true;
      if (type !== "warning" && type !== "warn") return false;
      return phase !== "dev" || !allowedDevWarnings.some((pattern) => pattern.test(String(message?.text ?? "")));
    });
    if (bad.length !== 0) process.exit(24);
  ' "$console_file" "$errors_file" "$phase"
}
capture_diagnostics() {
  local session="$1" label="$2"
  local console_file="$browser_directory/${label}-console.json"
  local errors_file="$browser_directory/${label}-errors.json"
  local network_file="$browser_directory/${label}-network.json"
  ab "$session" console --json >"$console_file"
  ab "$session" errors --json >"$errors_file"
  ab "$session" network requests --json | redact_network_json >"$network_file"
  assert_browser_diagnostics "$console_file" "$errors_file" "$browser_phase"
  printf 'BROWSER_DIAGNOSTICS_PASS phase=%s session=%s label=%s\n' "$browser_phase" "$session" "$label"
}
capture_current_state() {
  local session="$1" label="$2"
  ab "$session" screenshot "$browser_directory/${label}.png" >/dev/null
  capture_diagnostics "$session" "$label"
}
new_session() {
  local session="$1"
  browser_sessions="$browser_sessions $session"
  ab "$session" set headers '{"Accept-Language":"pt-PT,pt;q=0.9"}' >/dev/null
  ab "$session" network route 'https://**' --abort >/dev/null
}
page_assert() {
  local session="$1" path="$2" expected="$3" viewport="$4" shot="$5"
  local width="${viewport%x*}" height="${viewport#*x}"
  local expected_js
  expected_js="$("$NODE" -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$expected")"
  ab "$session" set viewport "$width" "$height" >/dev/null
  ab "$session" open "$app_origin$path" >/dev/null
  ab "$session" wait 700 >/dev/null
  local actual_url content_state landmark_state overlay_state expected_state overflow_state
  actual_url="$(ab "$session" get url)"
  content_state="$(ab "$session" eval 'document.body.innerText.trim().length > 0 ? "HAS_CONTENT" : "BLANK"')"
  landmark_state="$(ab "$session" eval 'document.querySelector("main, [role=main], h1") ? "HAS_LANDMARK" : "NO_LANDMARK"')"
  overlay_state="$(ab "$session" eval 'document.querySelector("[data-nextjs-dialog], .vite-error-overlay, #webpack-dev-server-client-overlay") ? "ERROR_OVERLAY" : "OK"')"
  expected_state="$(ab "$session" eval "document.body.innerText.includes($expected_js) ? 'EXPECTED' : 'MISSING'")"
  overflow_state="$(ab "$session" eval 'document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1 ? "NO_OVERFLOW" : "OVERFLOW"')"
  if [[ "$actual_url" != *"$app_origin$path"* || "$content_state" != *HAS_CONTENT* || "$landmark_state" != *HAS_LANDMARK* || "$overlay_state" != *OK* || "$expected_state" != *EXPECTED* || "$overflow_state" != *NO_OVERFLOW* ]]; then
    printf 'BROWSER_STATE_FAIL session=%s path=%s url=%s content=%s landmark=%s overlay=%s expected=%s overflow=%s\n' \
      "$session" "$path" "$actual_url" "$content_state" "$landmark_state" "$overlay_state" "$expected_state" "$overflow_state" >&2
    return 1
  fi
  ab "$session" screenshot "$browser_directory/$shot" >/dev/null
  capture_diagnostics "$session" "${shot%.png}"
  printf 'BROWSER_STATE_PASS session=%s viewport=%s path=%s url=%s landmark=%s screenshot=%s\n' \
    "$session" "$viewport" "$path" "$actual_url" "$landmark_state" "$browser_directory/$shot"
}
assert_dashboard_geometry() {
  local session="$1" mode="$2" label="$3"
  local geometry_file="$browser_directory/${label}-geometry.txt"
  local geometry_state
  geometry_state="$(ab "$session" eval "(() => {
    const viewport = document.documentElement.clientWidth;
    const shell = document.querySelector('.dashboard-shell');
    const main = document.querySelector('.dashboard-main');
    const sidebar = document.querySelector('.dashboard-sidebar');
    const desktopNav = document.querySelector('.dashboard-sidebar__desktop');
    const mobileNav = document.querySelector('.dashboard-sidebar__mobile');
    const key = main?.querySelector('h1, .card, [class*=card]');
    if (!shell || !main || !sidebar || !desktopNav || !mobileNav || !key) return 'GEOMETRY_FAIL:missing';
    const within = (rect) => rect.left >= -1 && rect.right <= viewport + 1;
    const mainRect = main.getBoundingClientRect();
    const keyRect = key.getBoundingClientRect();
    const sidebarRect = sidebar.getBoundingClientRect();
    const desktopDisplay = getComputedStyle(desktopNav).display;
    const mobileDisplay = getComputedStyle(mobileNav).display;
    if ('$mode' === 'mobile') {
      const mobileRect = mobileNav.getBoundingClientRect();
      const navFits = mobileNav.scrollWidth <= mobileNav.clientWidth + 1;
      return viewport === 390 && within(mainRect) && mainRect.width > 320 &&
        within(keyRect) && keyRect.width > 160 && within(mobileRect) &&
        mobileRect.width > 320 && navFits && desktopDisplay === 'none' && mobileDisplay !== 'none'
        ? 'GEOMETRY_PASS:mobile' : 'GEOMETRY_FAIL:mobile';
    }
    const columns = getComputedStyle(shell).gridTemplateColumns.split(/\\s+/);
    const firstColumn = Number.parseFloat(columns[0]);
    return viewport === 1440 && getComputedStyle(shell).display === 'grid' &&
      Math.abs(firstColumn - 260) <= 1 && Math.abs(sidebarRect.width - 260) <= 1 &&
      mainRect.left >= 259 && mainRect.right <= viewport + 1 && mainRect.width > 1000 &&
      within(keyRect) && keyRect.width > 160 && desktopDisplay !== 'none' && mobileDisplay === 'none'
      ? 'GEOMETRY_PASS:desktop' : 'GEOMETRY_FAIL:desktop';
  })()")"
  printf '%s\n' "$geometry_state" >"$geometry_file"
  [[ "$geometry_state" == *"GEOMETRY_PASS:$mode"* ]] || {
    printf 'DASHBOARD_GEOMETRY_FAIL session=%s mode=%s state=%s\n' "$session" "$mode" "$geometry_state" >&2
    return 1
  }
  printf 'DASHBOARD_GEOMETRY_PASS phase=%s session=%s mode=%s\n' "$browser_phase" "$session" "$mode"
}
login_actor() {
  local session="$1" email="$2" next="$3"
  ab "$session" open "$app_origin/login?next=$next" >/dev/null
  ab "$session" fill '#login-email' "$email" >/dev/null
  ab "$session" fill '#login-pwd' "$fixture_password" >/dev/null
  ab "$session" click 'form:has(#login-email) button[type="submit"]' >/dev/null
  ab "$session" wait 1000 >/dev/null
}

public_session="fb-tailor-public-$$"
new_session "$public_session"
page_assert "$public_session" '/' 'Food Trucks, Catering e Bares para Eventos' '1440x900' 'public-home-desktop.png'
page_assert "$public_session" '/catalogo' 'Fornecedor A E2E' '1440x900' 'public-catalog-desktop.png'
page_assert "$public_session" '/catalogo/fornecedor-a-e2e' 'Fornecedor A E2E' '390x844' 'public-detail-mobile.png'
page_assert "$public_session" '/pedidos' 'Evento Corporativo E2E' '390x844' 'public-requests-mobile.png'

supplier_session="fb-tailor-supplier-a-$$"
new_session "$supplier_session"
login_actor "$supplier_session" "$supplier_a_email" '/dashboard/truck'
page_assert "$supplier_session" '/dashboard/truck' 'Fornecedor A E2E' '1440x900' 'supplier-dashboard.png'
assert_dashboard_geometry "$supplier_session" 'desktop' 'supplier-dashboard-desktop'
page_assert "$supplier_session" '/dashboard/truck/f2700000-0000-4000-8000-000000000010' 'Fornecedor A E2E' '1440x900' 'supplier-service.png'
ab "$supplier_session" open "$app_origin/dashboard/truck/oportunidades/f2700000-0000-4000-8000-000000000100" >/dev/null
ab "$supplier_session" fill 'input[name="proposed_price"]' '951' >/dev/null
ab "$supplier_session" fill 'input[name="estimated_servings"]' '100' >/dev/null
ab "$supplier_session" fill 'textarea[name="cover_message"]' 'Proposta local E2E com equipa completa e serviço confirmado para o evento.' >/dev/null
ab "$supplier_session" click 'form:has(input[name="proposed_price"]) button[type="submit"]' >/dev/null
ab "$supplier_session" wait 1200 >/dev/null
page_assert "$supplier_session" '/dashboard/truck/aplicacoes' 'Evento Corporativo E2E' '1440x900' 'supplier-application.png'

application_id="$("${psql_scratch[@]}" --tuples-only --no-align --command="select id from public.airfnb_applications where request_id='f2700000-0000-4000-8000-000000000100' and truck_id='f2700000-0000-4000-8000-000000000010';")"
[[ "$application_id" =~ ^[0-9a-f-]{36}$ ]] || { printf '%s\n' 'application browser mutation missing' >&2; exit 1; }

organizer_session="fb-tailor-organizer-$$"
new_session "$organizer_session"
login_actor "$organizer_session" "$organizer_email" '/dashboard/organizer'
page_assert "$organizer_session" '/dashboard/organizer' 'Evento Corporativo E2E' '1440x900' 'organizer-dashboard.png'
ab "$organizer_session" open "$app_origin/dashboard/organizer/pedidos/f2700000-0000-4000-8000-000000000100" >/dev/null
ab "$organizer_session" find text 'Aceitar' click >/dev/null
ab "$organizer_session" wait 1200 >/dev/null
accept_state="$("${psql_scratch[@]}" --tuples-only --no-align --field-separator=':' --command="select application.status, lock_fee.status from public.airfnb_applications application join public.airfnb_lock_fees lock_fee on lock_fee.application_id=application.id where application.id='$application_id'::uuid;")"
[[ "$accept_state" == 'accepted:pending' ]] || { printf 'acceptance state mismatch: %s\n' "$accept_state" >&2; exit 1; }
printf 'MARKETPLACE_BROWSER_TRANSITION_PASS application=%s state=%s\n' "$application_id" "$accept_state"

page_assert "$supplier_session" "/dashboard/truck/lock/$application_id" 'Lock-fee para confirmar' '390x844' 'supplier-lock-mobile.png'
assert_dashboard_geometry "$supplier_session" 'mobile' 'supplier-lock-mobile'

supplier_b_session="fb-tailor-supplier-b-$$"
new_session "$supplier_b_session"
login_actor "$supplier_b_session" "$supplier_b_email" '/dashboard/truck'
page_assert "$supplier_b_session" '/dashboard/truck' 'Fornecedor B E2E' '1440x900' 'supplier-b-dashboard.png'
ab "$supplier_b_session" open "$app_origin/dashboard/truck/f2700000-0000-4000-8000-000000000010" >/dev/null
ab "$supplier_b_session" wait 700 >/dev/null
[[ "$(ab "$supplier_b_session" eval 'document.body.innerText.includes("SENTINELA PRIVADA FORNECEDOR B") ? "LEAK" : "NO_LEAK"')" == *NO_LEAK* ]] || exit 1
[[ "$(ab "$supplier_b_session" eval 'document.body.innerText.includes("Fornecedor A E2E") ? "LEAK" : "NO_LEAK"')" == *NO_LEAK* ]] || exit 1
capture_current_state "$supplier_b_session" 'supplier-cross-tenant-denial'
printf '%s\n' 'SUPPLIER_CROSS_TENANT_BROWSER_DENIAL_PASS'

admin_session="fb-tailor-admin-$$"
new_session "$admin_session"
login_actor "$admin_session" "$admin_email" '/admin'
page_assert "$admin_session" '/admin' 'Fornecedor Pendente E2E' '1440x900' 'admin-dashboard.png'
ab "$organizer_session" open "$app_origin/admin" >/dev/null
ab "$organizer_session" wait 700 >/dev/null
[[ "$(ab "$organizer_session" get url)" == *'/dashboard/organizer'* ]] || { printf '%s\n' 'organizer admin denial failed' >&2; exit 1; }
capture_current_state "$organizer_session" 'organizer-admin-denial'
printf '%s\n' 'ADMIN_BROWSER_BOUNDARY_PASS'

signup_session="fb-tailor-signup-$$"
new_session "$signup_session"
ab "$signup_session" open "$app_origin/signup" >/dev/null
ab "$signup_session" wait 800 >/dev/null
ab "$signup_session" fill '#signup-name' 'Novo Organizador E2E' >/dev/null
ab "$signup_session" fill '#signup-email' "$signup_email" >/dev/null
ab "$signup_session" fill '#signup-pwd' "$fixture_password" >/dev/null
ab "$signup_session" focus '#signup-pwd' >/dev/null
ab "$signup_session" press Enter >/dev/null
for _ in {1..80}; do
  [[ "$(ab "$signup_session" get url)" == *'/onboarding/organizer'* ]] && break
  sleep 0.25
done
if [[ "$(ab "$signup_session" get url)" != *'/onboarding/organizer'* ]]; then
  signup_validity="$(ab "$signup_session" eval 'document.querySelector("form:has(#signup-email)")?.checkValidity() ? "VALID" : "INVALID"')"
  signup_error="$(ab "$signup_session" eval '(() => { const value=document.querySelector(".error")?.innerText ?? ""; if (!value) return "NO_VISIBLE_ERROR"; if (value.includes("não conseguimos definir o teu papel")) return "PROFILE_UPDATE_ERROR"; if (value.includes("Confirma o teu email")) return "NO_IMMEDIATE_SESSION"; return "AUTH_RESPONSE_ERROR"; })()')"
  printf 'signup onboarding route failed validity=%s error=%s\n' "$signup_validity" "$signup_error" >&2
  exit 1
fi
capture_current_state "$signup_session" 'signup-onboarding'
printf '%s\n' 'AUTH_SIGNUP_BROWSER_PASS'

submit_same_origin_logout "$organizer_session"
ab "$organizer_session" open "$app_origin/dashboard/organizer" >/dev/null
ab "$organizer_session" wait 600 >/dev/null
logout_redirect="$(ab "$organizer_session" get url)"
[[ "$logout_redirect" == *'/login?next=/dashboard'* ]] || { printf 'logout protected redirect failed url=%s\n' "$logout_redirect" >&2; exit 1; }
capture_current_state "$organizer_session" 'logout-protected-redirect'
printf '%s\n' 'AUTH_LOGOUT_BROWSER_PASS'

if rg -n 'supabase\.co|stripe\.com|api\.stripe|hooks\.stripe' "$request_log" "$browser_directory" >/dev/null 2>&1; then
  printf '%s\n' 'remote Supabase/Stripe network evidence detected' >&2
  exit 1
fi
printf '%s\n' 'LOCAL_ONLY_NETWORK_PASS remote_supabase_stripe_responses=0'

# The lock screen is proven above. Payment must exercise the real shared
# server-only service; the fixture never manufactures a successful browser result.
ab "$supplier_session" open "$app_origin/dashboard/truck/lock/$application_id" >/dev/null
ab "$supplier_session" scrollintoview 'form:has(button.btn-pill) button.btn-pill' >/dev/null
ab "$supplier_session" focus 'form:has(button.btn-pill) button.btn-pill' >/dev/null
ab "$supplier_session" press Enter >/dev/null
ab "$supplier_session" wait 1500 >/dev/null
payment_state="$("${psql_scratch[@]}" --tuples-only --no-align --field-separator=':' --command="select lock_fee.status, booking.status from public.airfnb_lock_fees lock_fee join public.airfnb_bookings booking on booking.application_id=lock_fee.application_id where lock_fee.application_id='$application_id'::uuid;")"
[[ "$payment_state" == 'paid:confirmed' ]] || { printf 'LOCAL_DEV_PAYMENT_PENDING_APP_FIX state=%s url=%s\n' "$payment_state" "$(ab "$supplier_session" get url)" >&2; exit 1; }
printf 'LOCAL_DEV_PAYMENT_BROWSER_PASS state=%s\n' "$payment_state"
capture_current_state "$supplier_session" 'supplier-payment-confirmed'
printf '%s\n' 'LOCAL_E2E_DEV_BROWSER_PASS'

source_sha256_after="$(source_fingerprint)"
[[ "$source_sha256_after" == "$source_sha256_before" ]] || { printf '%s\n' 'source fingerprint changed' >&2; exit 1; }

for session in $browser_sessions; do "$AGENT_BROWSER" --session "$session" close >/dev/null 2>&1 || true; done
browser_sessions=''
stopped_app_pid="$app_pid"
kill -TERM "$app_pid"; wait "$app_pid" 2>/dev/null || true; app_pid=''
kill -0 "$stopped_app_pid" 2>/dev/null && { printf '%s\n' 'Next child still running' >&2; exit 1; }

(
  cd "$repository_root"
  exec env -i \
    PATH='/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin' LANG='C' LC_ALL='C' TMPDIR='/private/tmp' \
    NODE_ENV='test' NEXT_TELEMETRY_DISABLED='1' \
    NEXT_PUBLIC_SUPABASE_URL="$fixture_origin" NEXT_PUBLIC_SUPABASE_ANON_KEY="$anon_key" \
    SUPABASE_SERVICE_ROLE_KEY="$service_key" APP_URL="$app_origin" \
    NEXT_PUBLIC_OAUTH_PROVIDERS='' ENABLE_DEV_PAY='1' \
    "$PNPM" check
) >"$temporary_directory/check.stdout" 2>"$temporary_directory/check.stderr"
printf '%s\n' 'LOCAL_E2E_PNPM_CHECK_PASS'

(
  cd "$app_root"
  exec env -i \
    PATH='/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin' LANG='C' LC_ALL='C' TMPDIR='/private/tmp' \
    NODE_ENV='production' NEXT_TELEMETRY_DISABLED='1' \
    NEXT_PUBLIC_SUPABASE_URL="$fixture_origin" NEXT_PUBLIC_SUPABASE_ANON_KEY="$anon_key" \
    SUPABASE_SERVICE_ROLE_KEY="$service_key" APP_URL="$app_origin" \
    NEXT_PUBLIC_OAUTH_PROVIDERS='' ENABLE_DEV_PAY='1' \
    "$PNPM" build
) >"$temporary_directory/build.stdout" 2>"$temporary_directory/build.stderr"
printf '%s\n' 'LOCAL_E2E_LOOPBACK_BUILD_PASS'

# Exercise the built artifact with a fresh browser matrix. No development
# browser profile, cookie or runtime process is reused here.
browser_directory="$prod_browser_directory"
browser_phase='prod'
(
  cd "$app_root"
  exec env -i \
    PATH='/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin' LANG='C' LC_ALL='C' TMPDIR='/private/tmp' \
    NODE_ENV='production' NEXT_TELEMETRY_DISABLED='1' \
    NEXT_PUBLIC_SUPABASE_URL="$fixture_origin" NEXT_PUBLIC_SUPABASE_ANON_KEY="$anon_key" \
    SUPABASE_SERVICE_ROLE_KEY="$service_key" APP_URL="$app_origin" \
    NEXT_PUBLIC_OAUTH_PROVIDERS='' \
    "$repository_root/node_modules/.bin/next" start -H 127.0.0.1 -p "$app_port"
) >"$temporary_directory/prod-app.stdout" 2>"$temporary_directory/prod-app.stderr" &
app_pid=$!

for _ in {1..120}; do
  if curl --noproxy '*' --fail --silent "$app_origin/" >/dev/null 2>&1; then break; fi
  kill -0 "$app_pid" 2>/dev/null || { sed -n '1,100p' "$temporary_directory/prod-app.stderr" >&2; exit 1; }
  sleep 0.25
done
curl --noproxy '*' --fail --silent "$app_origin/" >/dev/null
printf 'LOCAL_E2E_PRODUCTION_SERVER_PASS app=%s\n' "$app_origin"

prod_public_session="fb-tailor-prod-public-$$"
new_session "$prod_public_session"
page_assert "$prod_public_session" '/' 'Food Trucks, Catering e Bares para Eventos' '1440x900' 'public-home-desktop.png'
page_assert "$prod_public_session" '/catalogo' 'Fornecedor A E2E' '1440x900' 'public-catalog-desktop.png'
page_assert "$prod_public_session" '/catalogo/fornecedor-a-e2e' 'Fornecedor A E2E' '390x844' 'public-detail-mobile.png'
page_assert "$prod_public_session" '/pedidos' 'Pedidos abertos' '390x844' 'public-requests-mobile.png'

prod_supplier_session="fb-tailor-prod-supplier-a-$$"
new_session "$prod_supplier_session"
login_actor "$prod_supplier_session" "$supplier_a_email" '/dashboard/truck'
page_assert "$prod_supplier_session" '/dashboard/truck' 'Fornecedor A E2E' '1440x900' 'supplier-dashboard.png'
assert_dashboard_geometry "$prod_supplier_session" 'desktop' 'supplier-dashboard-desktop'
page_assert "$prod_supplier_session" '/dashboard/truck/aplicacoes' 'Evento Corporativo E2E' '1440x900' 'supplier-application.png'
page_assert "$prod_supplier_session" "/dashboard/truck/lock/$application_id" 'Já está confirmado' '390x844' 'supplier-lock-paid-mobile.png'
assert_dashboard_geometry "$prod_supplier_session" 'mobile' 'supplier-lock-paid-mobile'
[[ "$(ab "$prod_supplier_session" eval 'document.body.innerText.includes("Marcar como pago") ? "DEV_CTA" : "NO_DEV_CTA"')" == *NO_DEV_CTA* ]] || { printf '%s\n' 'production dev payment CTA exposed' >&2; exit 1; }

prod_organizer_session="fb-tailor-prod-organizer-$$"
new_session "$prod_organizer_session"
login_actor "$prod_organizer_session" "$organizer_email" '/dashboard/organizer'
page_assert "$prod_organizer_session" '/dashboard/organizer' 'Evento Corporativo E2E' '1440x900' 'organizer-dashboard.png'
page_assert "$prod_organizer_session" '/dashboard/organizer/pedidos/f2700000-0000-4000-8000-000000000100' 'Fornecedor A E2E' '1440x900' 'organizer-request-accepted.png'

prod_supplier_b_session="fb-tailor-prod-supplier-b-$$"
new_session "$prod_supplier_b_session"
login_actor "$prod_supplier_b_session" "$supplier_b_email" '/dashboard/truck'
page_assert "$prod_supplier_b_session" '/dashboard/truck' 'Fornecedor B E2E' '1440x900' 'supplier-b-dashboard.png'
ab "$prod_supplier_b_session" open "$app_origin/dashboard/truck/f2700000-0000-4000-8000-000000000010" >/dev/null
ab "$prod_supplier_b_session" wait 700 >/dev/null
[[ "$(ab "$prod_supplier_b_session" eval 'document.body.innerText.includes("SENTINELA PRIVADA FORNECEDOR B") || document.body.innerText.includes("Fornecedor A E2E") ? "LEAK" : "NO_LEAK"')" == *NO_LEAK* ]] || exit 1
capture_current_state "$prod_supplier_b_session" 'supplier-cross-tenant-denial'

prod_admin_session="fb-tailor-prod-admin-$$"
new_session "$prod_admin_session"
login_actor "$prod_admin_session" "$admin_email" '/admin'
page_assert "$prod_admin_session" '/admin' 'Fornecedor Pendente E2E' '1440x900' 'admin-dashboard.png'
ab "$prod_organizer_session" open "$app_origin/admin" >/dev/null
ab "$prod_organizer_session" wait 700 >/dev/null
[[ "$(ab "$prod_organizer_session" get url)" == *'/dashboard/organizer'* ]] || exit 1
capture_current_state "$prod_organizer_session" 'organizer-admin-denial'

prod_signup_session="fb-tailor-prod-signup-$$"
new_session "$prod_signup_session"
ab "$prod_signup_session" open "$app_origin/signup" >/dev/null
ab "$prod_signup_session" fill '#signup-name' 'Novo Organizador E2E' >/dev/null
ab "$prod_signup_session" fill '#signup-email' "$signup_email" >/dev/null
ab "$prod_signup_session" fill '#signup-pwd' "$fixture_password" >/dev/null
ab "$prod_signup_session" focus '#signup-pwd' >/dev/null
ab "$prod_signup_session" press Enter >/dev/null
for _ in {1..80}; do
  [[ "$(ab "$prod_signup_session" get url)" == *'/onboarding/organizer'* ]] && break
  sleep 0.25
done
[[ "$(ab "$prod_signup_session" get url)" == *'/onboarding/organizer'* ]] || exit 1
capture_current_state "$prod_signup_session" 'signup-onboarding'

submit_same_origin_logout "$prod_organizer_session"
ab "$prod_organizer_session" open "$app_origin/dashboard/organizer" >/dev/null
ab "$prod_organizer_session" wait 600 >/dev/null
[[ "$(ab "$prod_organizer_session" get url)" == *'/login?next=/dashboard'* ]] || exit 1
capture_current_state "$prod_organizer_session" 'logout-protected-redirect'

if rg -n 'supabase\.co|stripe\.com|api\.stripe|hooks\.stripe' "$request_log" "$evidence_directory" >/dev/null 2>&1; then
  printf '%s\n' 'remote Supabase/Stripe network evidence detected' >&2
  exit 1
fi
rg -o 'https://[^" ]*(googleapis|gstatic|unsplash)[^" ]*' "$evidence_directory" >"$evidence_directory/blocked-third-party-assets.txt" || true
printf '%s\n' 'LOCAL_E2E_PRODUCTION_BROWSER_PASS'

for session in $browser_sessions; do "$AGENT_BROWSER" --session "$session" close >/dev/null 2>&1 || true; done
browser_sessions=''
stopped_app_pid="$app_pid"
kill -TERM "$app_pid"; wait "$app_pid" 2>/dev/null || true; app_pid=''
kill -0 "$stopped_app_pid" 2>/dev/null && { printf '%s\n' 'production Next child still running' >&2; exit 1; }

stopped_fixture_pid="$fixture_pid"
kill -TERM "$fixture_pid"; wait "$fixture_pid" 2>/dev/null || true; fixture_pid=''
kill -0 "$stopped_fixture_pid" 2>/dev/null && { printf '%s\n' 'fixture child still running' >&2; exit 1; }
printf '%s\n' 'ZERO_CHILD_PIDS_PASS count=0'
"$DROPDB" --host="$socket_directory" --port="$postgres_port" --maintenance-db=template1 -- "$scratch_database"
[[ "$(database_count "$scratch_database")" == 0 ]] || exit 1

residue="$(PGOPTIONS='-c default_transaction_read_only=on' "${psql_source[@]}" --tuples-only --no-align --command="select count(*) from pg_catalog.pg_database where datname like 'fb_tailor_e2e_%';")"
[[ "$residue" == 0 ]] || { printf 'scratch residue: %s\n' "$residue" >&2; exit 1; }
source_sha256_final="$(source_fingerprint)"
[[ "$source_sha256_final" == "$source_sha256_before" ]] || { printf '%s\n' 'final source fingerprint changed' >&2; exit 1; }
rm -f -- "$credentials_file"
if rg -n --pcre2 '"(?:authorization|apikey|cookie|set-cookie)"\s*:\s*"(?!\[REDACTED\])|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.' "$evidence_directory" >/dev/null 2>&1; then
  printf '%s\n' 'sensitive evidence refused' >&2
  exit 1
fi

cp "$temporary_directory/check.stdout" "$evidence_directory/check.stdout"
cp "$temporary_directory/check.stderr" "$evidence_directory/check.stderr"
cp "$temporary_directory/build.stdout" "$evidence_directory/build.stdout"
cp "$temporary_directory/build.stderr" "$evidence_directory/build.stderr"
"$NODE" -e '
  const fs = require("node:fs");
  const path = require("node:path");
  const crypto = require("node:crypto");
  const [root, source, gateway, driver, seed, sourceTest, pkg, stripe, follower] = process.argv.slice(1);
  const artifacts = {};
  const walk = (directory) => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const absolute = path.join(directory, entry.name);
      if (entry.isDirectory()) walk(absolute);
      else if (entry.name !== "manifest.json") {
        const relative = path.relative(root, absolute);
        artifacts[relative] = crypto.createHash("sha256").update(fs.readFileSync(absolute)).digest("hex");
      }
    }
  };
  walk(root);
  const manifest = {
    version: 1,
    source_fingerprint_before: source,
    source_fingerprint_after: source,
    dependencies: { stripe_sha256: stripe, follower_sha256: follower },
    candidate: { gateway_sha256: gateway, driver_sha256: driver, seed_sha256: seed, source_test_sha256: sourceTest, package_sha256: pkg },
    markers: { dev_browser: "pass", production_next_start: "pass", production_browser: "pass", pnpm_check: "pass", build: "pass", cleanup: "pass" },
    artifacts,
  };
  fs.writeFileSync(path.join(root, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`, { mode: 0o600 });
' "$evidence_directory" "$source_sha256_final" \
  "$(sha256_file "$fixture_server")" "$(sha256_file "$driver_file")" \
  "$(sha256_file "$seed_file")" "$(sha256_file "$source_test")" \
  "$(sha256_file "$repository_root/package.json")" "$stripe_sha256" "$follower_sha256"
find "$evidence_directory" -type f -exec chmod 600 {} +
manifest_sha256="$(sha256_file "$evidence_directory/manifest.json")"

printf 'SOURCE_FINGERPRINT_PASS before=%s after=%s\n' "$source_sha256_before" "$source_sha256_final"
printf 'ZERO_SCRATCH_RESIDUE_PASS count=%s\n' "$residue"
printf 'LOCAL_E2E_EVIDENCE_PASS path=%s manifest_sha256=%s\n' "$evidence_directory" "$manifest_sha256"
printf 'LOCAL_E2E_GO_LIVE_DRIVER_PASS gateway_sha256=%s seed_sha256=%s source_test_sha256=%s driver_sha256=%s\n' \
  "$(sha256_file "$fixture_server")" "$(sha256_file "$seed_file")" "$(sha256_file "$source_test")" "$(sha256_file "$driver_file")"
