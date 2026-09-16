#!/usr/bin/env bash
set -euo pipefail

# Upload extend_lock.rb to a Fly Rails machine and run StartTimerServer or AddTimeServer.
#
# Usage:
#   extend_lock.sh [--prod|--staging] [--email EMAIL] [--duration random|24h|7d|SECONDS]
#                  [--count N] [--ids 388,12]
#
# Default email: TIME_VAULT_LOCK_EMAIL, or that key in backend/.env. --email overrides.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
RUBY_FILE="$SCRIPT_DIR/extend_lock.rb"

APP="dc-backend"
EMAIL=""
EMAIL_FROM_FLAG=0
DURATION="random"
COUNT="1"
IDS=""

usage() {
  cat <<'EOF'
Usage: extend_lock.sh [options]

  --prod              Production Fly app (dc-backend, default)
  --staging           Staging Fly app (dc-backend-staging)
  --app NAME          Explicit Fly app name
  --email EMAIL       Account that owns the photos (overrides TIME_VAULT_LOCK_EMAIL)
  --duration SPEC     random (default, 24h–7d), seconds, or 24h / 7d / 90m
  --count N           Number of random eligible photos (default: 1; ignored if --ids)
  --ids ID[,ID...]    Specific LeveragePhoto ids (must belong to --email)
                      Already-locked photos get AddTimeServer; drafts/unlocked
                      get StartTimerServer (first encrypt or relock).
  -h, --help          Show this help

Default owner email: TIME_VAULT_LOCK_EMAIL (environment or backend/.env).
EOF
}

load_email_from_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local line
  line="$(grep -E '^[[:space:]]*TIME_VAULT_LOCK_EMAIL=' "$file" | tail -n1 || true)"
  [[ -n "$line" ]] || return 0
  local val="${line#*=}"
  val="${val%$'\r'}"
  val="${val%\"}"
  val="${val#\"}"
  val="${val%\'}"
  val="${val#\'}"
  TIME_VAULT_LOCK_EMAIL="$val"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prod) APP="dc-backend"; shift ;;
    --staging) APP="dc-backend-staging"; shift ;;
    --app)
      APP="${2:?--app requires a name}"
      shift 2
      ;;
    --email)
      EMAIL="${2:?--email requires an address}"
      EMAIL_FROM_FLAG=1
      shift 2
      ;;
    --duration)
      DURATION="${2:?--duration requires a value}"
      shift 2
      ;;
    --count)
      COUNT="${2:?--count requires a number}"
      shift 2
      ;;
    --ids)
      IDS="${2:?--ids requires at least one id}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$EMAIL_FROM_FLAG" -eq 0 ]]; then
  if [[ -z "${TIME_VAULT_LOCK_EMAIL:-}" ]]; then
    load_email_from_env_file "$REPO_ROOT/.env"
  fi
  if [[ -z "${TIME_VAULT_LOCK_EMAIL:-}" ]]; then
    load_email_from_env_file "$REPO_ROOT/backend/.env"
  fi
  EMAIL="${TIME_VAULT_LOCK_EMAIL:-}"
fi

if [[ -z "$EMAIL" ]]; then
  echo "Set TIME_VAULT_LOCK_EMAIL or pass --email" >&2
  exit 1
fi

if [[ ! -f "$RUBY_FILE" ]]; then
  echo "Missing runner: $RUBY_FILE" >&2
  exit 1
fi

B64="$(base64 < "$RUBY_FILE" | tr -d '\n')"

REMOTE=$(cat <<EOF
printf %s '$B64' | base64 -d > /tmp/extend_lock.rb && \
ADD_TIME_EMAIL='$EMAIL' ADD_TIME_DURATION='$DURATION' ADD_TIME_COUNT='$COUNT' ADD_TIME_IDS='$IDS' \
/rails/bin/rails runner /tmp/extend_lock.rb
EOF
)

exec fly ssh console -a "$APP" -C "sh -c $(printf '%q' "$REMOTE")"
