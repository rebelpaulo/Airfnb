#!/usr/bin/env bash
# Upsert an explicit allowlist of local variables into one Vercel project.
# Values come from the invoking environment first, then .env.local. The script
# never sources the file or prints environment values and request payloads.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${VERCEL_SOURCE_ENV_FILE:-${ROOT_DIR}/.env.local}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing local environment file." >&2
  exit 1
fi

read_local_value() {
  local requested_key="$1"
  local current="${!requested_key-}"
  local line raw

  if [ -n "$current" ]; then
    REPLY="$current"
    return 0
  fi

  REPLY=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      "${requested_key}="*)
        raw="${line#*=}"
        if [[ "$raw" == \"*\" && "$raw" == *\" ]]; then
          raw="${raw:1:${#raw}-2}"
        elif [[ "$raw" == \'*\' && "$raw" == *\' ]]; then
          raw="${raw:1:${#raw}-2}"
        fi
        REPLY="$raw"
        return 0
        ;;
    esac
  done < "$ENV_FILE"
}

require_setting() {
  local key="$1"
  read_local_value "$key"
  if [ -z "$REPLY" ]; then
    echo "Missing required bootstrap setting: $key" >&2
    exit 1
  fi
  printf -v "$key" '%s' "$REPLY"
}

TOKEN="${VERCEL_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  echo "VERCEL_TOKEN must be provided by the invoking shell." >&2
  exit 1
fi

require_setting VERCEL_PROJECT_ID
require_setting VERCEL_TEAM_ID
require_setting VERCEL_ENV_TARGETS
require_setting VERCEL_ENV_ALLOWLIST
read_local_value VERCEL_PLAIN_ENV_KEYS
VERCEL_PLAIN_ENV_KEYS="$REPLY"

IFS=',' read -r -a TARGETS <<< "$VERCEL_ENV_TARGETS"
if [ "${#TARGETS[@]}" -eq 0 ]; then
  echo "At least one Vercel environment target is required." >&2
  exit 1
fi
for target in "${TARGETS[@]}"; do
  case "$target" in
    production|preview|development) ;;
    *)
      echo "Unsupported Vercel environment target." >&2
      exit 1
      ;;
  esac
done

IFS=',' read -r -a ALLOWLIST <<< "$VERCEL_ENV_ALLOWLIST"
if [ "${#ALLOWLIST[@]}" -eq 0 ]; then
  echo "VERCEL_ENV_ALLOWLIST must name at least one variable." >&2
  exit 1
fi

is_plain_key() {
  local candidate="$1"
  local plain_key
  IFS=',' read -r -a PLAIN_KEYS <<< "$VERCEL_PLAIN_ENV_KEYS"
  for plain_key in "${PLAIN_KEYS[@]}"; do
    if [ "$candidate" = "$plain_key" ]; then return 0; fi
  done
  return 1
}

build_payload() {
  local key="$1" type="$2" targets="$3" value="$4"
  printf '%s' "$value" | python3 -c '
import json
import sys

value = sys.stdin.read()
targets = sys.argv[3].split(",")
print(json.dumps({
    "key": sys.argv[1],
    "value": value,
    "type": sys.argv[2],
    "target": targets,
}))
' "$key" "$type" "$targets"
}

upsert_key() {
  local key="$1" value="$2" type="$3"
  if ! build_payload "$key" "$type" "$VERCEL_ENV_TARGETS" "$value" | \
    curl --silent --show-error --fail \
      --variable '%VERCEL_TOKEN' \
      -X POST "https://api.vercel.com/v10/projects/${VERCEL_PROJECT_ID}/env?teamId=${VERCEL_TEAM_ID}&upsert=true" \
      --expand-header "Authorization: Bearer {{VERCEL_TOKEN}}" \
      -H "Content-Type: application/json" \
      --data-binary @- >/dev/null; then
    echo "Failed to upsert one allowlisted variable." >&2
    return 1
  fi
}

count=0
for key in "${ALLOWLIST[@]}"; do
  if [[ ! "$key" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
    echo "The Vercel allowlist contains an invalid variable name." >&2
    exit 1
  fi
  case "$key" in
    VERCEL_TOKEN|VERCEL_PROJECT_ID|VERCEL_TEAM_ID|VERCEL_ENV_*|VERCEL_PLAIN_ENV_KEYS)
      echo "Bootstrap-control variables cannot be deployed." >&2
      exit 1
      ;;
  esac

  read_local_value "$key"
  value="$REPLY"
  if [ -z "$value" ]; then
    echo "An allowlisted variable is missing or empty: $key" >&2
    exit 1
  fi
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo "Multiline environment values are not supported." >&2
    exit 1
  fi

  type="encrypted"
  if is_plain_key "$key"; then type="plain"; fi
  upsert_key "$key" "$value" "$type"
  count=$((count + 1))
done

echo "Upserted ${count} allowlisted variables. Trigger a deployment to apply them."
