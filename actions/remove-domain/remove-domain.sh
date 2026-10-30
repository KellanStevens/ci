#!/usr/bin/env bash
# Detach a Workers custom domain. This also removes its DNS record.
#
# Usage: remove-domain.sh <hostname>
# Needs CLOUDFLARE_API_TOKEN. Reads CLOUDFLARE_ACCOUNT_ID, or finds the account
# from the zone of the hostname, which needs Zone Read on the token.
#
# A missing domain is not an error, so this can run more than once.
set -euo pipefail

host=$1
if ! [[ "$host" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]; then
  echo "::error::\"$host\" is not a hostname."
  exit 1
fi

auth="Authorization: Bearer $CLOUDFLARE_API_TOKEN"
cf=https://api.cloudflare.com/client/v4

account=${CLOUDFLARE_ACCOUNT_ID:-}
if [ -z "$account" ]; then
  # Try each parent of the hostname until one is a zone: for
  # pr-1.example.co.za, that is pr-1.example.co.za, example.co.za, co.za.
  name=$host
  while [[ "$name" == *.* ]]; do
    account=$(curl -fsS -H "$auth" --get --data-urlencode "name=$name" "$cf/zones" |
      jq -r '.result[0].account.id // empty')
    [ -n "$account" ] && break
    name=${name#*.}
  done
  if [ -z "$account" ]; then
    echo "::error::The Cloudflare token cannot read the zone of $host. Set the account ID, or give the token Zone Read."
    exit 1
  fi
fi

api="$cf/accounts/$account/workers/domains"
ids=$(curl -fsS -H "$auth" --get --data-urlencode "hostname=$host" "$api" | jq -r '.result[].id')
if [ -z "$ids" ]; then
  echo "No custom domain for $host."
  exit 0
fi
for id in $ids; do
  curl -fsS -X DELETE -H "$auth" "$api/$id" >/dev/null
  echo "Removed $host ($id)."
done
