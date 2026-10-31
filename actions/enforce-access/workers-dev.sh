#!/usr/bin/env bash
# Check that a Worker is not also served on workers.dev or on its preview
# URLs, and turn them off if it is.
#
# Usage: workers-dev.sh <Worker name> <hostname>
#
# Access protects a hostname, so the workers.dev URL of the same Worker
# (<name>.<subdomain>.workers.dev) and its preview URLs skip Access. Wrangler
# turns both on unless wrangler.jsonc sets "workers_dev": false and
# "preview_urls": false. The hostname only finds the account.
#
# Needs CLOUDFLARE_API_TOKEN. Reads CLOUDFLARE_ACCOUNT_ID, or finds the account
# from the zone of the hostname, which needs Zone Read on the token. Exit 0 if
# both are off, 1 if one was on (and is now off).
set -euo pipefail

# shellcheck source=actions/lib/cloudflare.sh
. "$(dirname "$0")/../lib/cloudflare.sh"

worker=$1
host=$2
if ! [[ "$worker" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "::error::\"$worker\" is not a Worker name."
  exit 1
fi

cf_find_account "$host"
api="$cf_api/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/scripts/$worker/subdomain"

response=$(mktemp)
trap 'rm -f "$response"' EXIT
code=$(curl -sS -o "$response" -w '%{http_code}' -H "$cf_auth" "$api")
if [ "$code" != 200 ]; then
  echo "::error::Could not read the workers.dev settings of the Worker $worker (HTTP $code). Is it deployed, and does the token have Workers Scripts Read?"
  jq -r '.errors[]? | "\(.code): \(.message)"' "$response" 2>/dev/null || cat "$response"
  exit 1
fi

state=$(jq -c '.result | {enabled, previews_enabled}' "$response")
if [ "$state" = '{"enabled":false,"previews_enabled":false}' ]; then
  echo "$worker is not on workers.dev or its preview URLs."
  exit 0
fi

curl -fsS -X POST -H "$cf_auth" -H "Content-Type: application/json" \
  --data '{"enabled":false,"previews_enabled":false}' "$api" >/dev/null
echo "::error::$worker was public on workers.dev or its preview URLs ($state), past Access. Turned them off. Set \"workers_dev\": false and \"preview_urls\": false in wrangler.jsonc, also in the Wrangler environment, so that the next deploy does not turn them on again."
exit 1
