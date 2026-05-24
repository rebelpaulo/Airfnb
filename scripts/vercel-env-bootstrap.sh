#!/usr/bin/env bash
# Push the 4 Vercel env vars for the Air F&B project in one go.
#
# Reads the secret from .env.local in the project root, so the value never
# leaves your machine — you provide both the token and the destination.
#
# Usage:
#   VERCEL_TOKEN=vcp_xxx bash scripts/vercel-env-bootstrap.sh
#
# Re-running is safe: Vercel upserts on the same key/target.
#
# We intentionally do NOT accept the token as a positional argument: that
# leaks it into the shell history and `ps`-visible argv. Use the env var.
set -euo pipefail

TOKEN="${VERCEL_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  echo "Set VERCEL_TOKEN: VERCEL_TOKEN=vcp_xxx bash $0" >&2
  exit 1
fi

PROJECT="prj_mxkyrnNWddSBACXA1Li0CqlBlszn"
TEAM="team_HMhjZyN0EUJD0KwRqfWwIURp"

ENV_FILE="$(cd "$(dirname "$0")/.." && pwd)/.env.local"
if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE — make sure SUPABASE_SERVICE_ROLE_KEY is set there." >&2
  exit 1
fi
SERVICE_ROLE=$(grep -E '^SUPABASE_SERVICE_ROLE_KEY=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
if [ -z "$SERVICE_ROLE" ]; then
  echo "SUPABASE_SERVICE_ROLE_KEY not found in $ENV_FILE" >&2
  exit 1
fi

post_var() {
  local key="$1" value="$2" type="$3"
  local payload
  payload=$(python3 -c '
import json, sys
print(json.dumps({
  "key":    sys.argv[1],
  "value":  sys.argv[2],
  "type":   sys.argv[3],
  "target": ["production","preview","development"],
}))' "$key" "$value" "$type")

  local status
  # `set +e` so we can capture the exit status without `set -e` aborting before
  # we get to inspect it; restore right after.
  set +e
  curl --silent --show-error --fail \
    -X POST "https://api.vercel.com/v10/projects/${PROJECT}/env?teamId=${TEAM}&upsert=true" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$payload" >/dev/null
  status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    echo "  ✗ $key  (curl exit $status)" >&2
    return $status
  fi
  echo "  ✓ $key  ($type, ${#value} chars)"
}

echo "Pushing 4 env vars to Vercel project airfnb…"
post_var "NEXT_PUBLIC_SUPABASE_URL"      "https://rvcvyeodglovmptcuyiz.supabase.co" "plain"
post_var "NEXT_PUBLIC_SUPABASE_ANON_KEY" "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ2Y3Z5ZW9kZ2xvdm1wdGN1eWl6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDY1MzE0MTEsImV4cCI6MjA2MjEwNzQxMX0.nxD3rsoaYbLJratlmxJvaiUq8iKwXFr8-BPCmxfQBv0" "encrypted"
post_var "SUPABASE_SERVICE_ROLE_KEY"     "$SERVICE_ROLE" "encrypted"
post_var "APP_URL"                       "https://airfnb-originaly-gmailcoms-projects.vercel.app" "plain"
echo "Done. Trigger a redeploy in Vercel (or push a new commit)."
