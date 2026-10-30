#!/usr/bin/env bash
# Delete a preview Worker and its custom domains.
#
# Usage: delete-preview.sh <Worker name> <hostname>...
# Needs CLOUDFLARE_API_TOKEN. Reads CLOUDFLARE_ACCOUNT_ID, or finds the account
# from the zone of the first hostname, which needs Zone Read on the token.
#
# A missing domain or Worker is not an error, so this can run more than once
# for the same pull request. Any other failure is: the API, not the wording of
# a Wrangler message, says whether the Worker is missing.
set -euo pipefail

# shellcheck source=actions/lib/cloudflare.sh
. "$(dirname "$0")/../lib/cloudflare.sh"

name=$1
shift
if ! [[ "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "::error::\"$name\" is not a Worker name."
  exit 1
fi
if [ "$#" -eq 0 ]; then
  echo "::error::No hostname for $name."
  exit 1
fi

cf_find_account "$1"

# Detach the domains first, so that no hostname points at a deleted Worker.
for host in "$@"; do
  "$(dirname "$0")/../remove-domain/remove-domain.sh" "$host"
done

# force=true deletes the Worker even if another Worker binds to it, as
# `wrangler delete --force` did.
response=$(mktemp)
code=$(curl -sS -o "$response" -w '%{http_code}' -X DELETE -H "$cf_auth" \
  "$cf_api/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/scripts/$name?force=true")
if [ "$code" = 200 ]; then
  echo "Deleted the Worker $name."
# 10007 is "Worker not found". A draft pull request never gets a preview, so
# the Worker can be missing.
elif [ "$code" = 404 ] && jq -e 'any(.errors[]?; .code == 10007)' "$response" >/dev/null 2>&1; then
  echo "::notice::No preview Worker $name to delete."
else
  echo "::error::Could not delete the Worker $name (HTTP $code)."
  jq -r '.errors[]? | "\(.code): \(.message)"' "$response" 2>/dev/null || cat "$response"
  exit 1
fi
