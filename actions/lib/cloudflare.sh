# shellcheck shell=bash
# Shared by the scripts of the actions that call the Cloudflare API. Source
# it, do not run it. Needs CLOUDFLARE_API_TOKEN.

cf_api=https://api.cloudflare.com/client/v4
cf_auth="Authorization: Bearer $CLOUDFLARE_API_TOKEN"

# cf_find_account <hostname>
#
# Set and export CLOUDFLARE_ACCOUNT_ID. Keep it if it is set, or find the
# account from the zone of the hostname, which needs Zone Read on the token.
# Exported, so that the scripts this one runs do not look it up again.
cf_find_account() {
  local host=$1 name
  if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
    # Try each parent of the hostname until one is a zone: for
    # pr-1.example.co.za, that is pr-1.example.co.za, example.co.za, co.za.
    name=$host
    while [[ "$name" == *.* ]]; do
      CLOUDFLARE_ACCOUNT_ID=$(curl -fsS -H "$cf_auth" --get --data-urlencode "name=$name" "$cf_api/zones" |
        jq -r '.result[0].account.id // empty')
      [ -n "$CLOUDFLARE_ACCOUNT_ID" ] && break
      name=${name#*.}
    done
    if [ -z "$CLOUDFLARE_ACCOUNT_ID" ]; then
      echo "::error::The Cloudflare token cannot read the zone of $host. Set the account ID, or give the token Zone Read."
      exit 1
    fi
  fi
  # It goes into API paths.
  if ! [[ "$CLOUDFLARE_ACCOUNT_ID" =~ ^[0-9a-f]{32}$ ]]; then
    echo "::error::\"$CLOUDFLARE_ACCOUNT_ID\" is not a Cloudflare account ID."
    exit 1
  fi
  export CLOUDFLARE_ACCOUNT_ID
}
