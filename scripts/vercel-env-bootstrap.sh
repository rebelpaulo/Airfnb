#!/usr/bin/env bash
# Push the 4 Vercel env vars for the Air F&B project in one go.
#
# Reads the secret from .env.local in the project root, so the value never
# leaves your machine (you provide it; you POST it directly to Vercel).
#
# Usage:
#   VERCEL_TOKEN=vcp_xxx bash scripts/vercel-env-bootstrap.sh
# or
#   bash scripts/vercel-env-bootstrap.sh vcp_xxx
#
# Re-running is safe — Vercel upserts on the same key/target.
set -euo pipefail

TOKEN="${VERCEL_TOKEN:-${1:-}}"
if [ -z "$TOKEN" ]; then
  echo "Pass a Vercel token: VERCEL_TOKEN=vcp_xxx $0   (or)   $0 vcp_xxx" >&2
  exit 1
fi

PROJECT="prj_mxkyrnNWddSBACXA1Li0CqlBlszn"
TEAM="team_HMhjZyN0EUJD0KwRqfWwIURp"

# Read SUPABASE_SERVICE_ROLE_KEY from .env.local without echoing it
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
  curl --silent --show-error --fail \
    -X POST "https://api.vercel.com/v10/projects/${PROJECT}/env?teamId=${TEAM}&upsert=true" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c '
import json, sys
print(json.dumps({
  "key":    sys.argv[1],
  "value":  sys.argv[2],
  "type":   sys.argv[3],
  "target": ["production","preview","development"],
}))' "$key" "$value" "$type")" >/dev/null \
    && echo "  ✓ $key  ($type, ${#value} chars)" \
    || echo "  ✗ $key"
}

echo "Pushing 4 env vars to Vercel project airfnb…"
post_var "NEXT_PUBLIC_SUPABASE_URL"      "https://rvcvyeodglovmptcuyiz.supabase.co" "plain"
post_var "NEXT_PUBLIC_SUPABASE_ANON_KEY" "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ2Y3Z5ZW9kZ2xvdm1wdGN1eWl6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDY1MzE0MTEsImV4cCI6MjA2MjEwNzQxMX0.nxD3rsoaYbLJratlmxJvaiUq8iKwXFr8-BPCmxfQBv0" "encrypted"
post_var "SUPABASE_SERVICE_ROLE_KEY"     "$SERVICE_ROLE" "encrypted"
post_var "APP_URL"                       "https://airfnb-originaly-gmailcoms-projects.vercel.app" "plain"
echo "Done. Trigger a redeploy in Vercel (or push a new commit)."
