#!/usr/bin/env bash
# Check that Cloudflare Access protects a hostname, and take the site down if
# it does not.
#
# Usage: enforce-access.sh <hostname> <remove|keep> [<Worker name>]
#
# With a Worker name, a failed check deletes that preview Worker and its
# domain (delete-preview). Without one, it detaches the domain only
# (remove-domain). Needs CLOUDFLARE_API_TOKEN, and Wrangler for a Worker name.
# Reads CLOUDFLARE_ACCOUNT_ID.
#
# A site that answers without a login is always taken down. When the site
# cannot be reached, so Access is neither proven nor disproven, <remove> takes
# it down too, and <keep> leaves it up. Either way, this exits non-zero
# unless Access protects the site: 1 if it is public, 2 if it cannot be
# reached.
set -euo pipefail

host=$1
on_unreachable=$2
worker=${3:-}

if [ "$on_unreachable" != remove ] && [ "$on_unreachable" != keep ]; then
  echo "::error::on-unreachable must be \"remove\" or \"keep\", not \"$on_unreachable\"."
  exit 1
fi

actions=$(dirname "$0")/..

status=0
"$actions/check-access/check-access.sh" "$host" || status=$?
if [ "$status" -eq 0 ]; then
  exit 0
fi

# check-access.sh exits 1 for a public site. Treat any other failure as not
# reachable.
if [ "$status" -ne 1 ]; then
  status=2
  if [ "$on_unreachable" = keep ]; then
    echo "::warning::Could not check Access on $host. Keeping the site, as on-unreachable is keep."
    exit "$status"
  fi
  echo "::warning::Could not check Access on $host. Taking the site down, as on-unreachable is remove."
fi

if [ -n "$worker" ]; then
  "$actions/delete-preview/delete-preview.sh" "$worker" "$host"
else
  "$actions/remove-domain/remove-domain.sh" "$host"
fi
exit "$status"
