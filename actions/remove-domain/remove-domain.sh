#!/usr/bin/env bash
# Detach a Workers custom domain. This also removes its DNS record.
#
# Usage: remove-domain.sh <hostname>
# Needs CLOUDFLARE_API_TOKEN. Reads CLOUDFLARE_ACCOUNT_ID, or finds the account
# from the zone of the hostname, which needs Zone Read on the token.
#
# A missing domain is not an error, so this can run more than once.
set -euo pipefail

# shellcheck source=actions/lib/cloudflare.sh
. "$(dirname "$0")/../lib/cloudflare.sh"

host=$1
if ! [[ "$host" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]; then
  echo "::error::\"$host\" is not a hostname."
  exit 1
fi

cf_find_account "$host"

api="$cf_api/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/domains"
ids=$(curl -fsS -H "$cf_auth" --get --data-urlencode "hostname=$host" "$api" | jq -r '.result[].id')
if [ -z "$ids" ]; then
  echo "No custom domain for $host."
  exit 0
fi
for id in $ids; do
  curl -fsS -X DELETE -H "$cf_auth" "$api/$id" >/dev/null
  echo "Removed $host ($id)."
done
