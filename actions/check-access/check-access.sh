#!/usr/bin/env bash
# Check that Cloudflare Access protects a hostname: a request with no login
# must be sent to the Access login page.
#
# Usage: check-access.sh <hostname>
#
# Exit 0 if Access protects it, 1 if it is public, 2 if it cannot be reached.
# A new custom domain can take a few seconds to answer, so try for a while
# before giving up.
set -euo pipefail

host=$1
url="https://$host/"

for attempt in $(seq 1 10); do
  result=$(curl -sS -o /dev/null --max-time 10 -w '%{http_code} %{redirect_url}' "$url" 2>&1) || result="000 $result"
  code=${result%% *}
  location=${result#* }
  case "$code" in
    301 | 302 | 303 | 307 | 308)
      if [[ "$location" =~ ^https://[a-z0-9-]+\.cloudflareaccess\.com/ ]]; then
        echo "Access protects $url."
        exit 0
      fi
      echo "::error::$url redirects to $location, not to the Access login."
      exit 1
      ;;
    2* | 4*)
      echo "::error::$url answered $code without a login."
      exit 1
      ;;
    *)
      echo "Attempt $attempt: $url gave $result. Trying again."
      sleep 10
      ;;
  esac
done

echo "::error::Could not reach $url to check Access."
exit 2
